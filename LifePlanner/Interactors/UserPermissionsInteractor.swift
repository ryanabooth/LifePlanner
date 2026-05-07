import Foundation
import UserNotifications

enum Permission {
    case notifications
}

extension Permission {
    enum Status: Equatable {
        case unknown
        case notRequested
        case granted
        case denied
    }
}

protocol UserPermissionsInteractor: AnyObject {
    func resolveStatus(for permission: Permission)
    func request(permission: Permission)
}

protocol SystemNotificationsSettings {
    var authorizationStatus: UNAuthorizationStatus { get }
}

protocol SystemNotificationsCenter {
    func currentSettings() async -> SystemNotificationsSettings
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

extension UNNotificationSettings: SystemNotificationsSettings { }
extension UNUserNotificationCenter: SystemNotificationsCenter {
    func currentSettings() async -> any SystemNotificationsSettings {
        await notificationSettings()
    }
}

final class RealUserPermissionsInteractor: UserPermissionsInteractor {

    private let appState: Store<AppState>
    private let openAppSettings: () -> Void
    private let notificationCenter: SystemNotificationsCenter

    init(appState: Store<AppState>,
         notificationCenter: SystemNotificationsCenter = UNUserNotificationCenter.current(),
         openAppSettings: @escaping () -> Void
    ) {
        self.appState = appState
        self.notificationCenter = notificationCenter
        self.openAppSettings = openAppSettings
    }

    func resolveStatus(for permission: Permission) {
        let keyPath = AppState.permissionKeyPath(for: permission)
        let currentStatus = appState[keyPath]
        guard currentStatus == .unknown else { return }
        let appState = appState
        switch permission {
        case .notifications:
            Task { @MainActor in
                appState[keyPath] = await notificationsPermissionStatus()
            }
        }
    }

    func request(permission: Permission) {
        let keyPath = AppState.permissionKeyPath(for: permission)
        let currentStatus = appState[keyPath]
        guard currentStatus != .denied else {
            openAppSettings()
            return
        }
        switch permission {
        case .notifications:
            Task {
                await requestNotificationsPermission()
            }
        }
    }
}

extension UNAuthorizationStatus {
    var map: Permission.Status {
        switch self {
        case .denied: return .denied
        case .authorized: return .granted
        case .notDetermined, .provisional, .ephemeral: return .notRequested
        @unknown default: return .notRequested
        }
    }
}

private extension RealUserPermissionsInteractor {

    func notificationsPermissionStatus() async -> Permission.Status {
        await notificationCenter.currentSettings().authorizationStatus.map
    }

    func requestNotificationsPermission() async {
        let center = notificationCenter
        let isGranted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        appState[\.permissions.notifications] = isGranted ? .granted : .denied
    }
}

final class StubUserPermissionsInteractor: UserPermissionsInteractor {
    func resolveStatus(for permission: Permission) {}
    func request(permission: Permission) {}
}

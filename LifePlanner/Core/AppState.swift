import SwiftUI

struct AppState: Equatable {
    var routing = ViewRouting()
    var system = System()
    var permissions = Permissions()
}

extension AppState {
    struct ViewRouting: Equatable {
        var selectedTab: MainTab = .farm
        /// Set by a notification deep link; consumed (and cleared) by the tab
        /// that owns the entity so it can present the detail/edit screen.
        var pendingDeepLink: DeepLinkTarget? = nil
    }
}

/// An entity a notification tap should surface. Tab routing is derived from the
/// case, so handling one of these both switches tabs and opens the detail.
enum DeepLinkTarget: Equatable {
    case habit(UUID)
    case task(UUID)
    case farm
}

extension AppState {
    struct System: Equatable {
        var isActive: Bool = false
        var keyboardHeight: CGFloat = 0
    }
}

extension AppState {
    struct Permissions: Equatable {
        var notifications: Permission.Status = .unknown
    }

    static func permissionKeyPath(for permission: Permission) -> WritableKeyPath<AppState, Permission.Status> {
        switch permission {
        case .notifications:
            return \AppState.permissions.notifications
        }
    }
}

func == (lhs: AppState, rhs: AppState) -> Bool {
    lhs.routing == rhs.routing
        && lhs.system == rhs.system
        && lhs.permissions == rhs.permissions
}

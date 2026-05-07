import SwiftUI

struct AppState: Equatable {
    var routing = ViewRouting()
    var system = System()
    var permissions = Permissions()
}

extension AppState {
    struct ViewRouting: Equatable {
        var selectedTab: MainTab = .tasks
    }
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

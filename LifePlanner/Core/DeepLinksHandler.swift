import Foundation

enum DeepLink: Equatable {
    case habit(UUID)
    case task(UUID)
    case farm

    init?(url: URL) {
        return nil
    }

    /// Build a deep link from a local-notification request identifier. The
    /// identifiers are minted in `NotificationScheduler`:
    ///   - `habit-reminder-<uuid>` (and `…-wd<n>` weekday variants)
    ///   - `task-due-<uuid>`
    ///   - `plot-alert-<uuid>` → routes to the Farm tab
    init?(notificationIdentifier id: String) {
        if let rest = id.dropPrefixIfPresent("habit-reminder-") {
            // Strip any `-wd<n>` weekday suffix before parsing the UUID.
            let uuidPart: String
            if let suffix = rest.range(of: "-wd") {
                uuidPart = String(rest[..<suffix.lowerBound])
            } else {
                uuidPart = rest
            }
            guard let uuid = UUID(uuidString: uuidPart) else { return nil }
            self = .habit(uuid)
        } else if let rest = id.dropPrefixIfPresent("task-due-"),
                  let uuid = UUID(uuidString: rest) {
            self = .task(uuid)
        } else if id.hasPrefix("plot-alert-") {
            self = .farm
        } else {
            return nil
        }
    }

    var target: DeepLinkTarget {
        switch self {
        case .habit(let id): return .habit(id)
        case .task(let id):  return .task(id)
        case .farm:          return .farm
        }
    }
}

private extension String {
    /// Returns the remainder after `prefix`, or nil if the string doesn't start with it.
    func dropPrefixIfPresent(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

@MainActor
protocol DeepLinksHandler {
    func open(deepLink: DeepLink)
}

struct RealDeepLinksHandler: DeepLinksHandler {
    private let container: DIContainer

    init(container: DIContainer) {
        self.container = container
    }

    func open(deepLink: DeepLink) {
        let target = deepLink.target
        container.appState.bulkUpdate { state in
            switch target {
            case .habit: state.routing.selectedTab = .habits
            case .task:  state.routing.selectedTab = .tasks
            case .farm:  state.routing.selectedTab = .farm
            }
            state.routing.pendingDeepLink = target
        }
    }
}

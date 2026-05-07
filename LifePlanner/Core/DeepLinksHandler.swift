import Foundation

enum DeepLink: Equatable {
    init?(url: URL) {
        return nil
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
    }
}

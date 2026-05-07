import SwiftUI

struct RootViewAppearance: ViewModifier {

    @Environment(\.injected) private var injected: DIContainer
    @State private var isActive: Bool = false

    func body(content: Content) -> some View {
        content
            .blur(radius: isActive ? 0 : 10)
            .ignoresSafeArea()
            .onReceive(injected.appState.updates(for: \.system.isActive)) { isActive = $0 }
    }
}

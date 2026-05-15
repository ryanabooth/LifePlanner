import SwiftUI

@main
struct MainApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            appDelegate.rootView
        }
    }
}

extension AppEnvironment {
    var rootView: some View {
        Group {
            if isRunningTests {
                Text("Running unit tests")
            } else {
                ContentView()
                    .modifier(RootViewAppearance())
                    .modelContainer(modelContainer)
                    .inject(diContainer)
            }
        }
    }
}

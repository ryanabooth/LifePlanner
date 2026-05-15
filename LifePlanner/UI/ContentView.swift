import SwiftUI
import SwiftData

/// Root content view. Presents onboarding on first launch (clean install),
/// then shows `MainTabView`. Existing users (any data already in the store)
/// skip onboarding automatically — no regression for TestFlight upgraders.
struct ContentView: View {

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @Query private var habits: [DBModel.Habit]
    @Query private var tasks:  [DBModel.Task]
    @Query private var goals:  [DBModel.Goal]

    @State private var selectedTab: MainTab = .farm

    private var shouldShowOnboarding: Bool {
        !hasCompletedOnboarding && habits.isEmpty && tasks.isEmpty && goals.isEmpty
    }

    var body: some View {
        MainTabView(selection: $selectedTab)
            .fullScreenCover(isPresented: .constant(shouldShowOnboarding)) {
                OnboardingView { openGoals in
                    hasCompletedOnboarding = true
                    if openGoals { selectedTab = .goals }
                }
            }
    }
}

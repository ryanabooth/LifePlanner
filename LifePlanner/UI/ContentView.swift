import SwiftUI
import SwiftData

/// Root content view. Presents onboarding on first launch (clean install),
/// then shows `MainTabView`. Existing users (any data already in the store)
/// skip onboarding automatically — no regression for TestFlight upgraders.
struct ContentView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// Start-of-day (seconds since reference date) the back-fill prompt was last
    /// shown, so it only appears once per calendar day.
    @AppStorage("habitBackfill.lastPromptDay") private var lastPromptDay: Double = 0

    @Query private var habits: [DBModel.Habit]
    @Query private var tasks:  [DBModel.Task]
    @Query private var goals:  [DBModel.Goal]

    @State private var selectedTab: MainTab = .farm
    @State private var backfillHabits: [DBModel.Habit] = []
    @State private var showBackfillPrompt = false

    private let calendar = Calendar.current

    private var shouldShowOnboarding: Bool {
        !hasCompletedOnboarding && habits.isEmpty && tasks.isEmpty && goals.isEmpty
    }

    private var yesterday: Date {
        calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    /// Habits that were due yesterday and still aren't logged for it.
    private func unloggedYesterdayHabits() -> [DBModel.Habit] {
        let day = yesterday
        return habits.filter { $0.wasMissed(on: day, calendar: calendar) }
    }

    var body: some View {
        MainTabView(selection: $selectedTab)
            .fullScreenCover(isPresented: .constant(shouldShowOnboarding)) {
                OnboardingView { openGoals in
                    hasCompletedOnboarding = true
                    if openGoals { selectedTab = .goals }
                }
            }
            .sheet(isPresented: $showBackfillPrompt) {
                DailyHabitLogSheet(day: yesterday, habits: backfillHabits)
            }
            // A notification deep link sets routing.selectedTab; mirror it into
            // the TabView's binding so the correct tab comes forward.
            .onReceive(injected.appState.updates(for: \.routing.selectedTab)) { tab in
                if selectedTab != tab { selectedTab = tab }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { maybeShowBackfillPrompt() }
            }
            .onAppear { maybeShowBackfillPrompt() }
    }

    /// Show the back-fill prompt at most once per calendar day, and only when
    /// there's something to log and onboarding isn't covering the screen.
    private func maybeShowBackfillPrompt() {
        guard !shouldShowOnboarding, !showBackfillPrompt else { return }
        let today = calendar.startOfDay(for: Date()).timeIntervalSinceReferenceDate
        guard today != lastPromptDay else { return }
        let candidates = unloggedYesterdayHabits()
        guard !candidates.isEmpty else { return }
        backfillHabits = candidates
        showBackfillPrompt = true
        lastPromptDay = today
    }
}

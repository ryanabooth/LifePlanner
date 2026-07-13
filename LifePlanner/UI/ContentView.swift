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
    @State private var backfillItems: [BackfillItem] = []
    @State private var showBackfillPrompt = false

    private let calendar = Calendar.current

    private var shouldShowOnboarding: Bool {
        !hasCompletedOnboarding && habits.isEmpty && tasks.isEmpty && goals.isEmpty
    }

    /// One back-fill item per habit whose most recent *scheduled* day before
    /// today is still unlogged. Walks back to the last due day, so a weekdays
    /// habit surfaces its missed Friday when opened on a Monday.
    private func backfillCandidates() -> [BackfillItem] {
        let now = Date()
        return habits.compactMap { habit in
            guard let day = habit.mostRecentMissedDay(before: now, calendar: calendar) else { return nil }
            return BackfillItem(habit: habit, day: day)
        }
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
                DailyHabitLogSheet(items: backfillItems)
            }
            // A notification deep link sets routing.selectedTab; mirror it into
            // the TabView's binding so the correct tab comes forward.
            .onReceive(injected.appState.updates(for: \.routing.selectedTab)) { tab in
                if selectedTab != tab { selectedTab = tab }
            }
            // Keep routing.selectedTab in sync with the visible tab. Without this
            // it stays stale (default .farm) when the user switches tabs by hand;
            // then any re-render re-subscribes the publisher above, which re-emits
            // that stale value and yanks the user back to the farm — e.g. after
            // marking a task done or reordering. Syncing makes the re-emit a no-op.
            .onChange(of: selectedTab) { _, tab in
                injected.appState[\.routing.selectedTab] = tab
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { maybeShowBackfillPrompt() }
            }
            .onAppear {
                injected.appState[\.routing.selectedTab] = selectedTab
                maybeShowBackfillPrompt()
            }
    }

    /// Show the back-fill prompt at most once per calendar day, and only when
    /// there's something to log and onboarding isn't covering the screen.
    private func maybeShowBackfillPrompt() {
        guard !shouldShowOnboarding, !showBackfillPrompt else { return }
        let today = calendar.startOfDay(for: Date()).timeIntervalSinceReferenceDate
        guard today != lastPromptDay else { return }
        let candidates = backfillCandidates()
        guard !candidates.isEmpty else { return }
        backfillItems = candidates
        showBackfillPrompt = true
        lastPromptDay = today
    }
}

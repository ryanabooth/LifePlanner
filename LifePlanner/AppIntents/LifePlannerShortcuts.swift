import AppIntents

/// Registers the three Tiller actions with Siri and the Shortcuts app.
struct TillerShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowFarmIntent(),
            phrases: [
                "Open my farm in \(.applicationName)",
                "Show farm in \(.applicationName)"
            ],
            shortTitle: "Open Farm",
            systemImageName: "leaf"
        )
        AppShortcut(
            intent: RollTodaysQuestsIntent(),
            phrases: [
                "Roll my quests in \(.applicationName)",
                "Show today's quests in \(.applicationName)"
            ],
            shortTitle: "Today's Quests",
            systemImageName: "dice"
        )
        AppShortcut(
            intent: MarkHabitDoneIntent(),
            phrases: [
                "Log \(\.$habit) in \(.applicationName)",
                "Mark \(\.$habit) done in \(.applicationName)"
            ],
            shortTitle: "Log Habit",
            systemImageName: "checkmark.circle"
        )
    }
}

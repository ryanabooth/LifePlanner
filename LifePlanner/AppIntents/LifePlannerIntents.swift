import AppIntents
import SwiftData

// MARK: - Show Farm

struct ShowFarmIntent: AppIntent {

    static let title: LocalizedStringResource = "Open Farm"
    static let description = IntentDescription("Opens LifePlanner to your farm.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

// MARK: - Roll Today's Quests

/// Opening the app triggers the daily tick, which rolls quests idempotently.
struct RollTodaysQuestsIntent: AppIntent {

    static let title: LocalizedStringResource = "Roll Today's Quests"
    static let description = IntentDescription(
        "Opens LifePlanner and rolls today's quest batch if not yet rolled."
    )
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

// MARK: - Mark Habit Done

/// Logs today's completion for a specific habit without opening the app.
/// Farm contribution and quest auto-claim side effects happen the next time
/// the app foregrounds and runs its daily tick.
struct MarkHabitDoneIntent: AppIntent {

    static let title: LocalizedStringResource = "Log Habit"
    static let description = IntentDescription("Marks a daily habit as done for today.")

    @Parameter(title: "Habit")
    var habit: HabitEntity

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let container = try ModelContainer.appModelContainer()
        let context = ModelContext(container)
        let idString = habit.id
        let allHabits = (try? context.fetch(FetchDescriptor<DBModel.Habit>(
            predicate: #Predicate { !$0.archived }
        ))) ?? []
        guard let match = allHabits.first(where: { $0.id.uuidString == idString }) else {
            throw $habit.needsValueError("Habit not found. It may have been deleted.")
        }
        let today = Calendar.current.startOfDay(for: Date())
        let alreadyDone = match.isDone(on: today, calendar: .current)
        if !alreadyDone {
            context.insert(DBModel.HabitLogEntry(date: today, habit: match))
            try context.save()
        }
        return .result(
            value: !alreadyDone,
            dialog: alreadyDone
                ? IntentDialog(full: "\(match.title) was already logged today.", supporting: "Already done.")
                : IntentDialog(full: "\(match.title) logged for today! 🌱", supporting: "Logged.")
        )
    }
}

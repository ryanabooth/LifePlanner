import WidgetKit
import SwiftData

/// Reads today's quests from the shared SwiftData store and builds timeline entries.
///
/// ## App Group setup required
/// Before this widget can share data with the main app you must:
/// 1. Enable the "App Groups" capability on both the main app target and this
///    widget extension — use the same group ID (e.g. `group.com.lifeplanner.shared`).
/// 2. Pass `ModelConfiguration(url: appGroupURL)` to `ModelContainer.appModelContainer()`
///    in both the main app and here, replacing the default Documents-directory URL.
struct QuestProvider: TimelineProvider {

    func placeholder(in context: Context) -> QuestEntry {
        QuestEntry(
            date: Date(),
            gold: 120,
            quests: [
                QuestSnapshot(id: UUID(), kind: .task, title: "Complete: Write report",
                              goldReward: 10, isCompleted: false),
                QuestSnapshot(id: UUID(), kind: .habit, title: "Log: Morning run",
                              goldReward: 5, isCompleted: true),
                QuestSnapshot(id: UUID(), kind: .commonField, title: "Tend the common field",
                              goldReward: 3, isCompleted: false)
            ],
            weeklyProgress: 2,
            weeklyTarget: 5
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (QuestEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuestEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh at midnight so the widget shows a fresh batch each day.
        let midnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )
        let timeline = Timeline(entries: [entry], policy: .after(midnight))
        completion(timeline)
    }

    // MARK: - Private

    private func loadEntry() -> QuestEntry {
        guard let container = try? ModelContainer.appModelContainer() else {
            return emptyEntry()
        }
        let context = ModelContext(container)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today

        let allQuests = (try? context.fetch(FetchDescriptor<DBModel.Quest>(
            predicate: #Predicate { $0.day >= today && $0.day < tomorrow }
        ))) ?? []
        let allTasks = (try? context.fetch(FetchDescriptor<DBModel.Task>())) ?? []
        let allHabits = (try? context.fetch(FetchDescriptor<DBModel.Habit>())) ?? []
        let farmState = (try? context.fetch(FetchDescriptor<DBModel.FarmState>()))?.first

        // Weekly quest
        let weekComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let weekStart = cal.date(from: weekComps) ?? today
        let weekEnd = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? today
        let weeklyQuest = (try? context.fetch(FetchDescriptor<DBModel.Quest>(
            predicate: #Predicate { $0.slot == 3 && $0.day >= weekStart && $0.day < weekEnd }
        )))?.first

        let snapshots: [QuestSnapshot] = allQuests
            .filter { $0.slot < 3 }
            .sorted { $0.slot < $1.slot }
            .map { quest in
                QuestSnapshot(
                    id: quest.id,
                    kind: questKind(quest),
                    title: questTitle(quest, tasks: allTasks, habits: allHabits),
                    goldReward: quest.goldReward,
                    isCompleted: quest.state == .completed
                )
            }

        return QuestEntry(
            date: Date(),
            gold: farmState?.gold ?? 0,
            quests: snapshots,
            weeklyProgress: weeklyQuest?.progress ?? 0,
            weeklyTarget: weeklyQuest?.progressTarget ?? 5
        )
    }

    private func emptyEntry() -> QuestEntry {
        QuestEntry(date: Date(), gold: 0, quests: [], weeklyProgress: 0, weeklyTarget: 5)
    }

    private func questKind(_ quest: DBModel.Quest) -> QuestSnapshotKind {
        switch quest.kind {
        case .taskDue: return .task
        case .habitDue: return .habit
        case .commonFieldTend: return .commonField
        case .harvestMature: return .harvestMature
        case .weeklyHarvest: return .weeklyHarvest
        }
    }

    private func questTitle(
        _ quest: DBModel.Quest,
        tasks: [DBModel.Task],
        habits: [DBModel.Habit]
    ) -> String {
        switch quest.kind {
        case .taskDue:
            let task = tasks.first { $0.id == quest.referenceID }
            return "✓ " + (task?.title ?? "Complete task")
        case .habitDue:
            let habit = habits.first { $0.id == quest.referenceID }
            return "🔄 Log: " + (habit?.title ?? "Log habit")
        case .commonFieldTend:
            return "🌼 Tend the common field"
        case .harvestMature:
            return "🌾 Grow 2+ mature plots"
        case .weeklyHarvest:
            return "🌾 Weekly harvest"
        }
    }
}

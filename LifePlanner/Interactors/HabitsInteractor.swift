import Foundation
import SwiftData

struct HabitDraft {
    var title: String = ""
    var notes: String? = nil
    var frequency: HabitFrequency = .daily
    var reminderTime: Date? = nil
}

protocol HabitsInteractor {
    func add(_ draft: HabitDraft, in context: ModelContext)
    func update(_ habit: DBModel.Habit, with draft: HabitDraft, in context: ModelContext)
    func setArchived(_ habit: DBModel.Habit, archived: Bool, in context: ModelContext)
    func delete(_ habit: DBModel.Habit, in context: ModelContext)
    func toggleDone(_ habit: DBModel.Habit, on day: Date, in context: ModelContext)
}

enum StreakTuning {
    static let milestones = [7, 14, 30, 60, 100]

    static func bonus(at days: Int) -> Int {
        switch days {
        case 7:   return 10
        case 14:  return 20
        case 30:  return 50
        case 60:  return 100
        case 100: return 200
        default:  return 0
        }
    }
}

final class RealHabitsInteractor: HabitsInteractor {

    private let calendar: Calendar
    private let scheduler: NotificationScheduler
    private let economy: EconomyInteractor
    private let farm: FarmInteractor
    private let quests: QuestInteractor

    init(
        calendar: Calendar = .current,
        scheduler: NotificationScheduler = RealNotificationScheduler(),
        economy: EconomyInteractor = RealEconomyInteractor(),
        farm: FarmInteractor = StubFarmInteractor(),
        quests: QuestInteractor = StubQuestInteractor()
    ) {
        self.calendar = calendar
        self.scheduler = scheduler
        self.economy = economy
        self.farm = farm
        self.quests = quests
    }

    func add(_ draft: HabitDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let habit = DBModel.Habit(
            title: title,
            notes: draft.notes?.nilIfBlank,
            frequency: draft.frequency,
            reminderTime: draft.reminderTime
        )
        context.insert(habit)
        syncReminder(for: habit)
    }

    func update(_ habit: DBModel.Habit, with draft: HabitDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        habit.title = title
        habit.notes = draft.notes?.nilIfBlank
        habit.frequency = draft.frequency
        habit.reminderTime = draft.reminderTime
        habit.updatedAt = Date()
        syncReminder(for: habit)
    }

    func setArchived(_ habit: DBModel.Habit, archived: Bool, in context: ModelContext) {
        habit.archived = archived
        habit.updatedAt = Date()
        if archived {
            cancelReminder(for: habit)
        } else {
            syncReminder(for: habit)
        }
    }

    func delete(_ habit: DBModel.Habit, in context: ModelContext) {
        cancelReminder(for: habit)
        context.delete(habit)
    }

    func toggleDone(_ habit: DBModel.Habit, on day: Date, in context: ModelContext) {
        if let existing = habit.entry(on: day, calendar: calendar) {
            context.delete(existing)
            // Reversing a completion does not refund health — the contribution
            // already affected the plot's lastContribution timestamp. Keeping
            // the model write-once on completion avoids audit complexity.
        } else {
            let entry = DBModel.HabitLogEntry(
                date: calendar.startOfDay(for: day),
                habit: habit
            )
            context.insert(entry)
            let matured = farm.applyHabitCompletion(habit, in: context)
            quests.notifyCompletion(referenceID: habit.id, in: context)
            quests.checkFarmQuests(in: context)
            quests.trackMatureTransitions(count: matured, in: context)
        }
        habit.updatedAt = Date()
        recomputeStreak(for: habit, on: day)
        checkStreakMilestone(for: habit, in: context)
    }

    // MARK: - Streak helpers

    private func recomputeStreak(for habit: DBModel.Habit, on baseDay: Date) {
        let entryDays = Set((habit.entries ?? []).map { calendar.startOfDay(for: $0.date) })
        var streak = 0
        var expected = calendar.startOfDay(for: baseDay)
        while entryDays.contains(expected) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: expected) else { break }
            expected = prev
        }
        habit.currentStreak = streak
        if streak > habit.longestStreak { habit.longestStreak = streak }
    }

    private func checkStreakMilestone(for habit: DBModel.Habit, in context: ModelContext) {
        let streak = habit.currentStreak
        guard streak > 0 else { return }
        guard let milestone = StreakTuning.milestones
            .filter({ $0 <= streak && $0 > habit.lastStreakMilestone })
            .max()
        else { return }
        let bonus = StreakTuning.bonus(at: milestone)
        economy.credit(bonus, reason: "streak-\(habit.id)-\(milestone)", in: context)
        habit.lastStreakMilestone = milestone
        let title = habit.title
        Task.detached { [scheduler] in
            await scheduler.scheduleStreakMilestone(habitTitle: title, streak: milestone, bonus: bonus)
        }
    }

    private func syncReminder(for habit: DBModel.Habit) {
        let id = habit.id
        let title = habit.title
        if let time = habit.reminderTime, !habit.archived {
            Task.detached { [scheduler] in
                await scheduler.scheduleHabitReminder(habitID: id, title: title, time: time)
            }
        } else {
            Task.detached { [scheduler] in
                await scheduler.cancelHabitReminder(habitID: id)
            }
        }
    }

    private func cancelReminder(for habit: DBModel.Habit) {
        let id = habit.id
        Task.detached { [scheduler] in
            await scheduler.cancelHabitReminder(habitID: id)
        }
    }
}

final class StubHabitsInteractor: HabitsInteractor {
    func add(_ draft: HabitDraft, in context: ModelContext) {}
    func update(_ habit: DBModel.Habit, with draft: HabitDraft, in context: ModelContext) {}
    func setArchived(_ habit: DBModel.Habit, archived: Bool, in context: ModelContext) {}
    func delete(_ habit: DBModel.Habit, in context: ModelContext) {}
    func toggleDone(_ habit: DBModel.Habit, on day: Date, in context: ModelContext) {}
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import Foundation
import SwiftData

struct HabitDraft {
    var title: String = ""
    var notes: String? = nil
    var frequency: HabitFrequency = .daily
    /// Per-week target for `.weekly` cadence. Ignored when `frequency == .daily`.
    var weeklyTarget: Int = 3
    var reminderTime: Date? = nil
    /// ID of the single goal this habit is linked to, or nil for unlinked.
    var linkedGoalID: UUID? = nil
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
    private let achievements: AchievementInteractor

    init(
        calendar: Calendar = .current,
        scheduler: NotificationScheduler = RealNotificationScheduler(),
        economy: EconomyInteractor = RealEconomyInteractor(),
        farm: FarmInteractor = StubFarmInteractor(),
        quests: QuestInteractor = StubQuestInteractor(),
        achievements: AchievementInteractor = StubAchievementInteractor()
    ) {
        self.calendar = calendar
        self.scheduler = scheduler
        self.economy = economy
        self.farm = farm
        self.quests = quests
        self.achievements = achievements
    }

    func add(_ draft: HabitDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let habit = DBModel.Habit(
            title: title,
            notes: draft.notes?.nilIfBlank,
            frequency: draft.frequency,
            weeklyTarget: max(1, draft.weeklyTarget),
            reminderTime: draft.reminderTime
        )
        context.insert(habit)
        applyGoalLink(draft.linkedGoalID, to: habit, in: context)
        syncReminder(for: habit)
        quests.refreshTodaysCommonFieldSlots(in: context)
        context.saveQuietly()
    }

    func update(_ habit: DBModel.Habit, with draft: HabitDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        habit.title = title
        habit.notes = draft.notes?.nilIfBlank
        habit.frequency = draft.frequency
        habit.weeklyTarget = max(1, draft.weeklyTarget)
        habit.reminderTime = draft.reminderTime
        habit.updatedAt = Date()
        applyGoalLink(draft.linkedGoalID, to: habit, in: context)
        syncReminder(for: habit)
        context.saveQuietly()
    }

    func setArchived(_ habit: DBModel.Habit, archived: Bool, in context: ModelContext) {
        habit.archived = archived
        habit.updatedAt = Date()
        if archived {
            cancelReminder(for: habit)
        } else {
            syncReminder(for: habit)
        }
        context.saveQuietly()
    }

    func delete(_ habit: DBModel.Habit, in context: ModelContext) {
        cancelReminder(for: habit)
        context.delete(habit)
        context.saveQuietly()
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
            if habit.goals?.isEmpty != false { quests.notifyCommonFieldTend(in: context) }
            quests.checkFarmQuests(in: context)
            quests.trackMatureTransitions(count: matured, in: context)
        }
        habit.updatedAt = Date()
        recomputeStreak(for: habit, on: day)
        checkStreakMilestone(for: habit, in: context)
        achievements.checkAll(in: context)
        context.saveQuietly()
    }

    // MARK: - Streak helpers

    private func recomputeStreak(for habit: DBModel.Habit, on baseDay: Date) {
        let streak: Int
        switch habit.frequency {
        case .daily:
            streak = computeDailyStreak(for: habit, endingAt: baseDay)
        case .weekly:
            streak = computeWeeklyStreak(for: habit, endingAt: baseDay)
        }
        habit.currentStreak = streak
        if streak > habit.longestStreak { habit.longestStreak = streak }
    }

    private func computeDailyStreak(for habit: DBModel.Habit, endingAt baseDay: Date) -> Int {
        let entryDays = Set((habit.entries ?? []).map { calendar.startOfDay(for: $0.date) })
        var streak = 0
        var expected = calendar.startOfDay(for: baseDay)
        while entryDays.contains(expected) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: expected) else { break }
            expected = prev
        }
        return streak
    }

    /// Walks back week-by-week from the *current* ISO week, counting consecutive
    /// completed weeks. The current week gets a grace pass when it's mid-progress
    /// — only fully past weeks break the chain. `baseDay` is ignored because the
    /// streak should reflect "where you are now", not where the toggle landed
    /// (e.g. backfilling last Tuesday shouldn't reset the streak).
    private func computeWeeklyStreak(for habit: DBModel.Habit, endingAt baseDay: Date) -> Int {
        let target = max(1, habit.weeklyTarget)
        let entries = (habit.entries ?? []).map { $0.date }
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        guard var weekStart = calendar.date(from: comps) else { return 0 }
        var streak = 0
        var isCurrentWeek = true
        while true {
            guard let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            let inWeek = entries.filter { $0 >= weekStart && $0 < weekEnd }.count
            if inWeek >= target {
                streak += 1
            } else if !isCurrentWeek {
                break
            }
            // else: current week not yet complete — grace pass, don't break.
            isCurrentWeek = false
            guard let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) else { break }
            weekStart = prev
        }
        return streak
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

    /// Sets `habit.goals` to the single goal matching `goalID`, or clears it when
    /// `goalID` is nil. The many-to-many inverse on `Goal.linkedHabits` is updated
    /// automatically by SwiftData.
    private func applyGoalLink(_ goalID: UUID?, to habit: DBModel.Habit, in context: ModelContext) {
        guard let goalID else {
            habit.goals = []
            return
        }
        let descriptor = FetchDescriptor<DBModel.Goal>(predicate: #Predicate { $0.id == goalID })
        if let goal = try? context.fetch(descriptor).first {
            habit.goals = [goal]
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

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

final class RealHabitsInteractor: HabitsInteractor {

    private let calendar: Calendar
    private let scheduler: NotificationScheduler

    init(
        calendar: Calendar = .current,
        scheduler: NotificationScheduler = RealNotificationScheduler()
    ) {
        self.calendar = calendar
        self.scheduler = scheduler
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
        } else {
            let entry = DBModel.HabitLogEntry(
                date: calendar.startOfDay(for: day),
                habit: habit
            )
            context.insert(entry)
        }
        habit.updatedAt = Date()
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

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
    init(calendar: Calendar = .current) { self.calendar = calendar }

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
    }

    func update(_ habit: DBModel.Habit, with draft: HabitDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        habit.title = title
        habit.notes = draft.notes?.nilIfBlank
        habit.frequency = draft.frequency
        habit.reminderTime = draft.reminderTime
        habit.updatedAt = Date()
    }

    func setArchived(_ habit: DBModel.Habit, archived: Bool, in context: ModelContext) {
        habit.archived = archived
        habit.updatedAt = Date()
    }

    func delete(_ habit: DBModel.Habit, in context: ModelContext) {
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

import Foundation
import SwiftData

enum HabitFrequency: Int, Codable, CaseIterable, Identifiable {
    case daily = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .daily: return "Daily"
        }
    }
}

extension DBModel {
    @Model
    final class Habit {
        var id: UUID = UUID()
        var title: String = ""
        var notes: String? = nil
        var frequency: HabitFrequency = HabitFrequency.daily
        var reminderTime: Date? = nil
        var archived: Bool = false
        /// Number of consecutive days this habit has been logged ending today (or
        /// the last day it was toggled). Recomputed by `HabitsInteractor.toggleDone`.
        var currentStreak: Int = 0
        var longestStreak: Int = 0
        /// The highest streak-milestone day-count that has already been credited
        /// with a gold bonus. Prevents awarding the same milestone twice.
        var lastStreakMilestone: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \DBModel.HabitLogEntry.habit)
        var entries: [DBModel.HabitLogEntry]? = []

        var goals: [DBModel.Goal]? = []

        init(
            id: UUID = UUID(),
            title: String = "",
            notes: String? = nil,
            frequency: HabitFrequency = .daily,
            reminderTime: Date? = nil,
            archived: Bool = false,
            currentStreak: Int = 0,
            longestStreak: Int = 0,
            lastStreakMilestone: Int = 0,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.frequency = frequency
            self.reminderTime = reminderTime
            self.archived = archived
            self.currentStreak = currentStreak
            self.longestStreak = longestStreak
            self.lastStreakMilestone = lastStreakMilestone
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        func entry(on day: Date, calendar: Calendar = .current) -> DBModel.HabitLogEntry? {
            let start = calendar.startOfDay(for: day)
            return (entries ?? []).first { calendar.startOfDay(for: $0.date) == start }
        }

        func isDone(on day: Date, calendar: Calendar = .current) -> Bool {
            entry(on: day, calendar: calendar) != nil
        }
    }

    @Model
    final class HabitLogEntry {
        var id: UUID = UUID()
        var date: Date = Date()
        var habit: DBModel.Habit? = nil
        var createdAt: Date = Date()

        init(
            id: UUID = UUID(),
            date: Date = Date(),
            habit: DBModel.Habit? = nil,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.date = date
            self.habit = habit
            self.createdAt = createdAt
        }
    }
}

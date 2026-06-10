import Foundation
import SwiftData

enum HabitFrequency: Int, Codable, CaseIterable, Identifiable {
    case daily = 0
    /// Log `weeklyTarget` entries within an ISO week to count the week as "done".
    /// Streak measures consecutive completed weeks ending at the toggled date.
    case weekly = 1
    /// Due Monday–Friday only. Requires a log on each weekday; weekends are not
    /// due (no nag, and they don't break the streak).
    case weekdays = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .daily:    return "Daily"
        case .weekly:   return "Weekly"
        case .weekdays: return "Weekdays"
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
        /// Per-week target for `.weekly` cadence. Ignored when `frequency == .daily`.
        var weeklyTarget: Int = 1
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
            weeklyTarget: Int = 1,
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
            self.weeklyTarget = weeklyTarget
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

        /// Count of log entries in the ISO week containing `day`.
        func entriesInWeek(containing day: Date, calendar: Calendar = .current) -> Int {
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)
            guard let weekStart = calendar.date(from: comps),
                  let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart)
            else { return 0 }
            return (entries ?? []).filter { $0.date >= weekStart && $0.date < weekEnd }.count
        }

        /// Whether this habit is scheduled to be logged on `day`. Daily and
        /// weekly habits are always "due"; weekdays habits are due Mon–Fri only.
        func isDue(on day: Date, calendar: Calendar = .current) -> Bool {
            switch frequency {
            case .daily, .weekly:
                return true
            case .weekdays:
                return !calendar.isDateInWeekend(day)
            }
        }

        /// True if the week containing `day` meets the cadence target.
        /// Daily habits require a log on `day`; weekly habits require `weeklyTarget`
        /// entries that week; weekdays habits require a log on `day` when it's a
        /// weekday and are vacuously complete on weekends.
        func isWeekComplete(containing day: Date, calendar: Calendar = .current) -> Bool {
            switch frequency {
            case .daily:
                return isDone(on: day, calendar: calendar)
            case .weekly:
                return entriesInWeek(containing: day, calendar: calendar) >= weeklyTarget
            case .weekdays:
                guard isDue(on: day, calendar: calendar) else { return true }
                return isDone(on: day, calendar: calendar)
            }
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

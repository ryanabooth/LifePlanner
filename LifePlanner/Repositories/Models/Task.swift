import Foundation
import SwiftData

enum TaskSortOrder: String, CaseIterable {
    case dueDate
    case priority

    var label: String {
        switch self {
        case .dueDate: return "Due Date"
        case .priority: return "Priority"
        }
    }

    var symbolName: String {
        switch self {
        case .dueDate: return "calendar"
        case .priority: return "flag"
        }
    }
}

enum TaskRecurrence: Int, Codable, CaseIterable, Identifiable {
    case daily    = 0
    case weekdays = 1
    case weekly   = 2
    case monthly  = 3
    case yearly   = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .daily:    return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly:   return "Weekly"
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly"
        }
    }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while [1, 7].contains(calendar.component(.weekday, from: next)) {
                next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
            }
            return next
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }
}

enum TaskPriority: Int, Codable, CaseIterable, Identifiable, Comparable {
    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rawValue < rhs.rawValue }
    case low = 0
    case normal = 1
    case high = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }

    var symbolName: String {
        switch self {
        case .low: return "chevron.down"
        case .normal: return "equal"
        case .high: return "chevron.up"
        }
    }
}

extension DBModel {
    @Model
    final class Task {
        var id: UUID = UUID()
        var title: String = ""
        var notes: String? = nil
        var dueDate: Date? = nil
        // Stored as Int so SortDescriptor can sort it at the SQL level.
        var priorityRaw: Int = TaskPriority.normal.rawValue
        var isDone: Bool = false
        var completedAt: Date? = nil
        var tags: [String] = []
        var recurrenceRaw: Int? = nil
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        var goals: [DBModel.Goal]? = []

        init(
            id: UUID = UUID(),
            title: String = "",
            notes: String? = nil,
            dueDate: Date? = nil,
            priority: TaskPriority = .normal,
            isDone: Bool = false,
            completedAt: Date? = nil,
            tags: [String] = [],
            recurrence: TaskRecurrence? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.dueDate = dueDate
            self.priorityRaw = priority.rawValue
            self.isDone = isDone
            self.completedAt = completedAt
            self.tags = tags
            self.recurrenceRaw = recurrence?.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

// Computed wrappers live outside the @Model class so the macro never registers
// them as entity attributes — only the raw Int fields end up in the schema.
extension DBModel.Task {
    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var recurrence: TaskRecurrence? {
        get { recurrenceRaw.flatMap { TaskRecurrence(rawValue: $0) } }
        set { recurrenceRaw = newValue?.rawValue }
    }
}

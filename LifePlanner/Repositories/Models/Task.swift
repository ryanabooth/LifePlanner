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
        var priority: TaskPriority = TaskPriority.normal
        var isDone: Bool = false
        var completedAt: Date? = nil
        var tags: [String] = []
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
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.dueDate = dueDate
            self.priority = priority
            self.isDone = isDone
            self.completedAt = completedAt
            self.tags = tags
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

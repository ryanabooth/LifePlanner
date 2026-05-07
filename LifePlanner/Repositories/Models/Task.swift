import Foundation
import SwiftData

enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
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

import Foundation
import SwiftData

enum GoalStatus: Int, Codable, CaseIterable, Identifiable {
    case active = 0
    case paused = 1
    case done = 2
    case abandoned = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .done: return "Done"
        case .abandoned: return "Abandoned"
        }
    }

    var symbolName: String {
        switch self {
        case .active: return "target"
        case .paused: return "pause.circle"
        case .done: return "checkmark.seal"
        case .abandoned: return "xmark.seal"
        }
    }
}

extension DBModel {
    @Model
    final class Goal {
        var id: UUID = UUID()
        var title: String = ""
        var why: String? = nil
        var targetDate: Date? = nil
        var status: GoalStatus = GoalStatus.active
        /// What kind of farm element this goal manifests as. User-picked at create time.
        var farmElementType: FarmElementType = FarmElementType.crop
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        @Relationship(inverse: \DBModel.Task.goals)
        var linkedTasks: [DBModel.Task]? = []

        @Relationship(inverse: \DBModel.Habit.goals)
        var linkedHabits: [DBModel.Habit]? = []

        /// The farm plot allocated for this goal. Cascade-deleted when the goal is removed.
        /// `nil` until `FarmInteractor.bindPlot(to:)` allocates one.
        /// Inverse is declared on `FarmPlot.goal`.
        @Relationship(deleteRule: .cascade)
        var plot: DBModel.FarmPlot? = nil

        init(
            id: UUID = UUID(),
            title: String = "",
            why: String? = nil,
            targetDate: Date? = nil,
            status: GoalStatus = .active,
            farmElementType: FarmElementType = .crop,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.why = why
            self.targetDate = targetDate
            self.status = status
            self.farmElementType = farmElementType
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

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

        /// Optional numeric metric. `metricUnit` non-nil enables progress tracking
        /// (e.g. "miles", "pages"). `metricTarget == 0` means no fixed target.
        var metricUnit: String? = nil
        var metricTarget: Double = 0
        var metricValue: Double = 0

        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        @Relationship(inverse: \DBModel.Task.goals)
        var linkedTasks: [DBModel.Task]? = []

        @Relationship(inverse: \DBModel.Habit.goals)
        var linkedHabits: [DBModel.Habit]? = []

        @Relationship(deleteRule: .cascade, inverse: \DBModel.SubGoal.goal)
        var subGoals: [DBModel.SubGoal]? = []

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
            metricUnit: String? = nil,
            metricTarget: Double = 0,
            metricValue: Double = 0,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.why = why
            self.targetDate = targetDate
            self.status = status
            self.farmElementType = farmElementType
            self.metricUnit = metricUnit
            self.metricTarget = metricTarget
            self.metricValue = metricValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        /// Has a tracked metric (i.e. user set a unit).
        var hasMetric: Bool { (metricUnit?.isEmpty == false) }
        /// 0.0...1.0 normalized progress. Returns 0 when target is unset.
        var metricProgress: Double {
            guard metricTarget > 0 else { return 0 }
            return min(1.0, metricValue / metricTarget)
        }
    }

    /// A single ordered sub-goal under a parent `Goal`. Checking one off pumps
    /// health into the parent's plot (same magnitude as a task completion).
    @Model
    final class SubGoal {
        var id: UUID = UUID()
        var title: String = ""
        var isDone: Bool = false
        /// Display order within the parent. Ascending. Renumbered on reorder.
        var order: Int = 0
        var goal: DBModel.Goal? = nil
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(
            id: UUID = UUID(),
            title: String = "",
            isDone: Bool = false,
            order: Int = 0,
            goal: DBModel.Goal? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.isDone = isDone
            self.order = order
            self.goal = goal
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

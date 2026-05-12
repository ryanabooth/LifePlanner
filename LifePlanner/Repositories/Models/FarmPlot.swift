import Foundation
import SwiftData

/// What kind of thing lives on this plot. Drives sprite selection and decay rate.
enum FarmElementType: Int, Codable, CaseIterable, Identifiable {
    case crop = 0
    case animal = 1
    case tree = 2
    case structure = 3
    /// Singleton catch-all plot for unlinked habits/tasks. Never bound to a Goal.
    case commonField = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .crop: return "Crop"
        case .animal: return "Animal"
        case .tree: return "Tree"
        case .structure: return "Structure"
        case .commonField: return "Common Field"
        }
    }

    /// Whether the user can pick this type for a Goal. Common-field is reserved.
    var isUserSelectable: Bool { self != .commonField }
}

/// Visual / mechanical state of a plot. Driven by health and elapsed time.
enum PlotState: Int, Codable, CaseIterable {
    /// Reserved for un-bound plots; unused in v1.
    case empty = 0
    /// Bound, alive, health < mature threshold.
    case growing = 1
    /// Bound, alive, health >= mature threshold.
    case mature = 2
    /// Health hit 0 but recovery still possible.
    case withered = 3
    /// Withered too long — must be re-planted to revive.
    case dead = 4
}

extension DBModel {
    @Model
    final class FarmPlot {
        var id: UUID = UUID()
        /// Grid coordinates in the farm scene. (0,0) is bottom-left.
        var gridX: Int = 0
        var gridY: Int = 0
        var kind: FarmElementType = FarmElementType.crop
        /// 0-100. Drives state transitions and sprite tint.
        var health: Int = 50
        var state: PlotState = PlotState.growing
        /// nil for the common-field plot; otherwise points to a user Goal.
        @Relationship(inverse: \DBModel.Goal.plot)
        var goal: DBModel.Goal? = nil
        /// Last time a habit/task contributed health here. Drives decay.
        var lastContribution: Date? = nil
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(
            id: UUID = UUID(),
            gridX: Int = 0,
            gridY: Int = 0,
            kind: FarmElementType = .crop,
            health: Int = 50,
            state: PlotState = .growing,
            goal: DBModel.Goal? = nil,
            lastContribution: Date? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.gridX = gridX
            self.gridY = gridY
            self.kind = kind
            self.health = health
            self.state = state
            self.goal = goal
            self.lastContribution = lastContribution
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

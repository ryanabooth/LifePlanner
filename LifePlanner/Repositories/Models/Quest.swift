import Foundation
import SwiftData

/// What completing this quest requires.
enum QuestKind: Int, Codable, CaseIterable {
    /// Mark a specific Task done. `referenceID` = Task.id.
    case taskDue = 0
    /// Log a specific Habit today. `referenceID` = Habit.id.
    case habitDue = 1
    /// Generic tend-the-common-field quest. `referenceID` = nil.
    case commonFieldTend = 2
    /// Farm-state quest: have ≥ `QuestTuning.harvestMatureThreshold` mature
    /// non-common plots simultaneously. `referenceID` = nil.
    /// Auto-claimed by `QuestInteractor.checkFarmQuests` after any contribution.
    case harvestMature = 3
}

/// Lifecycle state for a daily quest slot.
enum QuestState: Int, Codable, CaseIterable {
    case active = 0
    case completed = 1
    case expired = 2
}

extension DBModel {
    /// A single daily-quest slot. `QuestInteractor` rolls 3 per day, indexed 0/1/2.
    @Model
    final class Quest {
        var id: UUID = UUID()
        /// Start-of-day key. All quests sharing this date are "today's quests".
        var day: Date = Date()
        /// 0, 1, or 2. Position in the daily UI.
        var slot: Int = 0
        var kind: QuestKind = QuestKind.commonFieldTend
        /// Task.id or Habit.id depending on `kind`; nil for commonFieldTend.
        var referenceID: UUID? = nil
        var goldReward: Int = 0
        var state: QuestState = QuestState.active
        /// Count of times the user re-rolled into this slot. Drives next re-roll cost.
        var rerollCount: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(
            id: UUID = UUID(),
            day: Date = Date(),
            slot: Int = 0,
            kind: QuestKind = .commonFieldTend,
            referenceID: UUID? = nil,
            goldReward: Int = 0,
            state: QuestState = .active,
            rerollCount: Int = 0,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.day = day
            self.slot = slot
            self.kind = kind
            self.referenceID = referenceID
            self.goldReward = goldReward
            self.state = state
            self.rerollCount = rerollCount
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

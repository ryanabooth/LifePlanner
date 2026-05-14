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
    /// Weekly quest: push `progressTarget` plots to mature state during the week.
    /// `progress` is incremented by `QuestInteractor.trackMatureTransitions`.
    /// Slot 3, day = ISO week start.
    case weeklyHarvest = 4
}

/// Lifecycle state for a daily quest slot.
enum QuestState: Int, Codable, CaseIterable {
    case active = 0
    case completed = 1
    case expired = 2
}

extension DBModel {
    /// A single quest slot. Daily slots are indexed 0–2; the weekly slot is 3.
    @Model
    final class Quest {
        var id: UUID = UUID()
        /// Start-of-day key for daily quests; ISO week-start for weekly quests.
        var day: Date = Date()
        /// 0–2 = daily slot; 3 = weekly slot.
        var slot: Int = 0
        var kind: QuestKind = QuestKind.commonFieldTend
        /// Task.id or Habit.id depending on `kind`; nil for farm-state quests.
        var referenceID: UUID? = nil
        var goldReward: Int = 0
        var state: QuestState = QuestState.active
        /// Count of times the user re-rolled into this slot. Drives next re-roll cost.
        var rerollCount: Int = 0
        /// Accumulated progress toward `progressTarget` (weekly quests only).
        var progress: Int = 0
        /// Required progress to auto-claim; 0 means not a progress quest.
        var progressTarget: Int = 0
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
            progress: Int = 0,
            progressTarget: Int = 0,
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
            self.progress = progress
            self.progressTarget = progressTarget
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

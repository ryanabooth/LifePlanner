import WidgetKit
import Foundation

/// Data snapshot passed to the widget view at each timeline refresh.
struct QuestEntry: TimelineEntry {
    let date: Date
    let gold: Int
    let quests: [QuestSnapshot]
    let weeklyProgress: Int
    let weeklyTarget: Int
}

/// A serializable summary of a single quest slot — safe to hand across the
/// widget extension boundary (no SwiftData model graph).
struct QuestSnapshot: Identifiable, Hashable {
    let id: UUID
    let kind: QuestSnapshotKind
    let title: String
    let goldReward: Int
    let isCompleted: Bool
}

enum QuestSnapshotKind: Hashable {
    case task, habit, commonField, harvestMature, weeklyHarvest
}

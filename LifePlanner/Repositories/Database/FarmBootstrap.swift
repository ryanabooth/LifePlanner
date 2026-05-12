import Foundation
import SwiftData

/// First-launch idempotent seed for the farm singletons:
/// - exactly one `FarmState`
/// - exactly one common-field `FarmPlot` at grid (0, 0)
///
/// Safe to call on every launch — fetches first and only inserts what's missing.
/// In Step 3 this is expected to migrate into `FarmInteractor`; until then it lives
/// here so the schema bump in Step 2 is exercised even with no UI yet.
enum FarmBootstrap {

    @MainActor
    static func seedSingletons(in context: ModelContext) {
        seedFarmStateIfNeeded(in: context)
        seedCommonFieldIfNeeded(in: context)
        if context.hasChanges {
            try? context.save()
        }
    }

    @MainActor
    private static func seedFarmStateIfNeeded(in context: ModelContext) {
        var fetch = FetchDescriptor<DBModel.FarmState>()
        fetch.fetchLimit = 1
        let existing = (try? context.fetch(fetch)) ?? []
        guard existing.isEmpty else { return }
        context.insert(DBModel.FarmState())
    }

    @MainActor
    private static func seedCommonFieldIfNeeded(in context: ModelContext) {
        // #Predicate can't compare enum cases directly, so fetch all plots and filter
        // in memory. Plot count is small (≤ user goals + 1) so this is fine.
        let allPlots = (try? context.fetch(FetchDescriptor<DBModel.FarmPlot>())) ?? []
        guard !allPlots.contains(where: { $0.kind == .commonField }) else { return }
        context.insert(DBModel.FarmPlot(
            gridX: 0,
            gridY: 0,
            kind: .commonField,
            health: 100,
            state: .mature
        ))
    }
}

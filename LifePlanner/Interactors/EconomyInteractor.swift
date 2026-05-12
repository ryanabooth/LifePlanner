import Foundation
import SwiftData

enum EconomyError: Error {
    case insufficientGold(have: Int, need: Int)
    case noFarmState
}

/// Single source of truth for gold balance. All farm-related currency reads and
/// writes go through here so we have one obvious place to log, audit, or later
/// expose to analytics.
protocol EconomyInteractor {
    func balance(in context: ModelContext) -> Int
    func credit(_ amount: Int, reason: String, in context: ModelContext)
    func spend(_ amount: Int, reason: String, in context: ModelContext) throws
}

final class RealEconomyInteractor: EconomyInteractor {

    func balance(in context: ModelContext) -> Int {
        farmState(in: context)?.gold ?? 0
    }

    func credit(_ amount: Int, reason: String, in context: ModelContext) {
        guard amount > 0, let state = farmState(in: context) else { return }
        state.gold += amount
        state.updatedAt = Date()
    }

    func spend(_ amount: Int, reason: String, in context: ModelContext) throws {
        guard amount >= 0 else { return }
        guard let state = farmState(in: context) else { throw EconomyError.noFarmState }
        guard state.gold >= amount else {
            throw EconomyError.insufficientGold(have: state.gold, need: amount)
        }
        state.gold -= amount
        state.updatedAt = Date()
    }

    private func farmState(in context: ModelContext) -> DBModel.FarmState? {
        var fetch = FetchDescriptor<DBModel.FarmState>()
        fetch.fetchLimit = 1
        return (try? context.fetch(fetch))?.first
    }
}

final class StubEconomyInteractor: EconomyInteractor {
    func balance(in context: ModelContext) -> Int { 0 }
    func credit(_ amount: Int, reason: String, in context: ModelContext) {}
    func spend(_ amount: Int, reason: String, in context: ModelContext) throws {}
}

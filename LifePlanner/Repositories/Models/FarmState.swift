import Foundation
import SwiftData

/// Singleton row holding cross-cutting farm state: gold balance, plot capacity,
/// and the last day we ran a decay tick. Exactly one row should exist at runtime;
/// `FarmInteractor.bootstrap` is responsible for creating it on first launch.
extension DBModel {
    @Model
    final class FarmState {
        var id: UUID = UUID()
        /// Starting balance for fresh installs. Lightweight-migration default
        /// — existing FarmState rows keep their current `gold` value, only
        /// freshly-inserted rows pick this up.
        var gold: Int = 100
        var plotCapacity: Int = 3
        /// Start-of-day timestamp for the most recent decay run. nil = no tick yet.
        var lastDecayTick: Date? = nil
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        // MARK: - Achievement counters (added v0.13.0)

        /// Cumulative gold credited across all time. Powers "Penny Pincher".
        var totalGoldEarned: Int = 0
        /// Cumulative gold spent across all time. Powers "Big Spender".
        var totalGoldSpent: Int = 0
        /// Number of times any plot has transitioned to .mature. Powers "Harvest Master".
        var totalMatureTransitions: Int = 0
        /// Number of dead plots ever replanted. Powers "Revived".
        var totalReplants: Int = 0

        init(
            id: UUID = UUID(),
            gold: Int = 100,
            plotCapacity: Int = 3,
            lastDecayTick: Date? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.gold = gold
            self.plotCapacity = plotCapacity
            self.lastDecayTick = lastDecayTick
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

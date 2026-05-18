import Foundation
import SwiftData

extension DBModel {
    /// Persists a purchased farm tool. Tools are always active once purchased —
    /// there is no equip / unequip flow. Their bonuses stack additively.
    @Model
    final class OwnedTool {
        var id: UUID = UUID()
        /// Matches a key in `ToolCatalog`. e.g. "watering_can_ii".
        var slug: String = ""
        var purchasedAt: Date = Date()

        init(slug: String, purchasedAt: Date = Date()) {
            self.slug = slug
            self.purchasedAt = purchasedAt
        }
    }
}

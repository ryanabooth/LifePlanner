import Foundation
import SwiftData

extension DBModel {
    /// A single achievement milestone. One row per slug; idempotent — once
    /// unlocked a slug is never re-inserted (AchievementInteractor checks first).
    @Model
    final class Achievement {
        var id: UUID = UUID()
        /// Matches a key in `AchievementCatalog`. e.g. "week_strong".
        var slug: String = ""
        var unlockedAt: Date = Date()

        init(slug: String, unlockedAt: Date = Date()) {
            self.slug = slug
            self.unlockedAt = unlockedAt
        }
    }
}

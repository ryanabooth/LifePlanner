import Foundation
import SwiftData

// MARK: - Catalog

/// Static definition of a single achievement milestone. The slug is the
/// primary key — it matches what gets persisted in `DBModel.Achievement`.
struct AchievementDefinition {
    let slug: String
    let emoji: String
    let title: String
    let description: String
}

/// All achievements the app can award. Order here determines display order
/// in `TrophyShelfView`. Slugs are stable identifiers — never rename them.
enum AchievementCatalog {
    static let all: [AchievementDefinition] = [
        // Farm milestones — driven by FarmState.totalMatureTransitions
        AchievementDefinition(
            slug: "first_harvest",
            emoji: "🌾",
            title: "First Harvest",
            description: "A plot reached maturity for the first time."
        ),
        AchievementDefinition(
            slug: "harvest_5",
            emoji: "🌾",
            title: "Bountiful",
            description: "Reached maturity 5 times total."
        ),
        AchievementDefinition(
            slug: "harvest_master",
            emoji: "🏆",
            title: "Harvest Master",
            description: "Reached maturity 50 times total."
        ),

        // Gold economy — driven by FarmState.totalGoldEarned
        AchievementDefinition(
            slug: "penny_pincher",
            emoji: "🪙",
            title: "Penny Pincher",
            description: "Earned 500 gold in total."
        ),
        AchievementDefinition(
            slug: "gold_rush",
            emoji: "💰",
            title: "Gold Rush",
            description: "Earned 5,000 gold in total."
        ),

        // Gold spending — driven by FarmState.totalGoldSpent
        AchievementDefinition(
            slug: "big_spender",
            emoji: "🛍️",
            title: "Big Spender",
            description: "Spent 500 gold in total."
        ),

        // Replanting — driven by FarmState.totalReplants
        AchievementDefinition(
            slug: "green_thumb",
            emoji: "🌱",
            title: "Green Thumb",
            description: "Replanted a dead plot for the first time."
        ),
        AchievementDefinition(
            slug: "revived",
            emoji: "💪",
            title: "Revived",
            description: "Replanted 5 plots in total."
        ),

        // Cosmetics — driven by OwnedCosmetic count
        AchievementDefinition(
            slug: "fashionista",
            emoji: "👗",
            title: "Fashionista",
            description: "Purchased your first cosmetic."
        ),
        AchievementDefinition(
            slug: "trendsetter",
            emoji: "🎩",
            title: "Trendsetter",
            description: "Purchased 5 cosmetics."
        ),

        // Habit streaks — driven by max(habit.currentStreak)
        AchievementDefinition(
            slug: "week_strong",
            emoji: "🔥",
            title: "Week Strong",
            description: "Maintained a 7-day habit streak."
        ),
        AchievementDefinition(
            slug: "month_strong",
            emoji: "🌟",
            title: "Month Strong",
            description: "Maintained a 30-day habit streak."
        ),
    ]

    static func definition(for slug: String) -> AchievementDefinition? {
        all.first { $0.slug == slug }
    }
}

// MARK: - Protocol

protocol AchievementInteractor {
    /// Check all achievement thresholds against current state. Inserts any
    /// newly earned `DBModel.Achievement` rows and fires unlock notifications.
    /// Idempotent — already-unlocked slugs are never re-inserted.
    func checkAll(in context: ModelContext)
}

// MARK: - Real implementation

final class RealAchievementInteractor: AchievementInteractor {

    private let scheduler: NotificationScheduler

    init(scheduler: NotificationScheduler = StubNotificationScheduler()) {
        self.scheduler = scheduler
    }

    func checkAll(in context: ModelContext) {
        let farmState = fetchFarmState(in: context)
        let unlockedSlugs = fetchUnlockedSlugs(in: context)
        let maxStreak = fetchMaxHabitStreak(in: context)
        let ownedCount = fetchOwnedCosmeticCount(in: context)

        let matureCount = farmState?.totalMatureTransitions ?? 0
        let goldEarned  = farmState?.totalGoldEarned ?? 0
        let goldSpent   = farmState?.totalGoldSpent ?? 0
        let replants    = farmState?.totalReplants ?? 0

        let checks: [(slug: String, met: Bool)] = [
            ("first_harvest",  matureCount >= 1),
            ("harvest_5",      matureCount >= 5),
            ("harvest_master", matureCount >= 50),
            ("penny_pincher",  goldEarned  >= 500),
            ("gold_rush",      goldEarned  >= 5_000),
            ("big_spender",    goldSpent   >= 500),
            ("green_thumb",    replants    >= 1),
            ("revived",        replants    >= 5),
            ("fashionista",    ownedCount  >= 1),
            ("trendsetter",    ownedCount  >= 5),
            ("week_strong",    maxStreak   >= 7),
            ("month_strong",   maxStreak   >= 30),
        ]

        for (slug, met) in checks {
            guard met, !unlockedSlugs.contains(slug) else { continue }
            context.insert(DBModel.Achievement(slug: slug))
            if let def = AchievementCatalog.definition(for: slug) {
                let emoji = def.emoji
                let title = def.title
                Task.detached { [scheduler] in
                    await scheduler.scheduleAchievementUnlocked(emoji: emoji, title: title)
                }
            }
        }
    }

    // MARK: - Private fetches

    private func fetchFarmState(in context: ModelContext) -> DBModel.FarmState? {
        var fetch = FetchDescriptor<DBModel.FarmState>()
        fetch.fetchLimit = 1
        return (try? context.fetch(fetch))?.first
    }

    private func fetchUnlockedSlugs(in context: ModelContext) -> Set<String> {
        let all = (try? context.fetch(FetchDescriptor<DBModel.Achievement>())) ?? []
        return Set(all.map(\.slug))
    }

    private func fetchMaxHabitStreak(in context: ModelContext) -> Int {
        let habits = (try? context.fetch(FetchDescriptor<DBModel.Habit>())) ?? []
        return habits.map(\.currentStreak).max() ?? 0
    }

    private func fetchOwnedCosmeticCount(in context: ModelContext) -> Int {
        ((try? context.fetch(FetchDescriptor<DBModel.OwnedCosmetic>())) ?? []).count
    }
}

// MARK: - Stub

final class StubAchievementInteractor: AchievementInteractor {
    func checkAll(in context: ModelContext) {}
}

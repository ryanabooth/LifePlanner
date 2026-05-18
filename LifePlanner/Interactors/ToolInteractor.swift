import Foundation
import SwiftData

// MARK: - Catalog

/// Static definition of a purchasable farm tool. Tools have no equip state —
/// they are always active once bought, and bonuses accumulate additively.
struct ToolDefinition {
    let slug: String
    let emoji: String
    let name: String
    let description: String
    let goldCost: Int
    /// Added to every habit contribution while this tool is owned.
    let habitBonus: Int
    /// Added to every task contribution while this tool is owned.
    let taskBonus: Int
}

enum ToolError: Error {
    case itemNotInCatalog
    case alreadyOwned
}

/// All purchasable tools. Slugs are stable — never rename them.
/// Frost Shield and Rain Dance Drum are deferred until their prerequisites ship.
enum ToolCatalog {
    static let all: [ToolDefinition] = [
        ToolDefinition(
            slug: "watering_can_ii",
            emoji: "🪣",
            name: "Watering Can II",
            description: "A sturdier can — habit contributions are boosted by +5 health.",
            goldCost: 75,
            habitBonus: 5,
            taskBonus: 0
        ),
        ToolDefinition(
            slug: "watering_can_iii",
            emoji: "🪣",
            name: "Watering Can III",
            description: "Professional grade — habit contributions are boosted by +10 health.",
            goldCost: 200,
            habitBonus: 10,
            taskBonus: 0
        ),
        ToolDefinition(
            slug: "sharper_hoe_ii",
            emoji: "⛏️",
            name: "Sharper Hoe II",
            description: "A well-sharpened hoe — task contributions are boosted by +5 health.",
            goldCost: 75,
            habitBonus: 0,
            taskBonus: 5
        ),
        ToolDefinition(
            slug: "sharper_hoe_iii",
            emoji: "⛏️",
            name: "Sharper Hoe III",
            description: "Master craftwork — task contributions are boosted by +10 health.",
            goldCost: 200,
            habitBonus: 0,
            taskBonus: 10
        ),
    ]

    static func item(slug: String) -> ToolDefinition? {
        all.first { $0.slug == slug }
    }
}

// MARK: - Protocol

protocol ToolInteractor {
    /// Purchase a tool by slug, debiting its gold cost. Throws if unknown or
    /// already owned, or on insufficient gold.
    func purchase(slug: String, in context: ModelContext) throws

    /// Cumulative habit-contribution bonus from all currently-owned tools.
    func habitBonus(in context: ModelContext) -> Int

    /// Cumulative task-contribution bonus from all currently-owned tools.
    func taskBonus(in context: ModelContext) -> Int

    /// All owned tool rows, ordered by purchase date.
    func allOwned(in context: ModelContext) -> [DBModel.OwnedTool]
}

// MARK: - Real implementation

final class RealToolInteractor: ToolInteractor {

    private let economy: EconomyInteractor

    init(economy: EconomyInteractor = RealEconomyInteractor()) {
        self.economy = economy
    }

    func purchase(slug: String, in context: ModelContext) throws {
        guard let def = ToolCatalog.item(slug: slug) else {
            throw ToolError.itemNotInCatalog
        }
        let owned = allOwned(in: context)
        guard !owned.contains(where: { $0.slug == slug }) else {
            throw ToolError.alreadyOwned
        }
        try economy.spend(def.goldCost, reason: "tool-\(slug)", in: context)
        context.insert(DBModel.OwnedTool(slug: slug))
        context.saveQuietly()
    }

    func habitBonus(in context: ModelContext) -> Int {
        allOwned(in: context)
            .compactMap { ToolCatalog.item(slug: $0.slug)?.habitBonus }
            .reduce(0, +)
    }

    func taskBonus(in context: ModelContext) -> Int {
        allOwned(in: context)
            .compactMap { ToolCatalog.item(slug: $0.slug)?.taskBonus }
            .reduce(0, +)
    }

    func allOwned(in context: ModelContext) -> [DBModel.OwnedTool] {
        let descriptor = FetchDescriptor<DBModel.OwnedTool>(
            sortBy: [SortDescriptor(\.purchasedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

// MARK: - Stub

final class StubToolInteractor: ToolInteractor {
    func purchase(slug: String, in context: ModelContext) throws {}
    func habitBonus(in context: ModelContext) -> Int { 0 }
    func taskBonus(in context: ModelContext) -> Int { 0 }
    func allOwned(in context: ModelContext) -> [DBModel.OwnedTool] { [] }
}

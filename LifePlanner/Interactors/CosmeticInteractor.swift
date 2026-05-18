import Foundation
import SwiftData

enum CosmeticError: Error {
    case itemNotInCatalog
    case alreadyOwned
}

/// Manages purchasing and equipping cosmetic items. All gold debits go
/// through `EconomyInteractor` so the balance stays consistent.
protocol CosmeticInteractor {
    /// Purchase a catalog item and debit its gold cost. Throws
    /// `CosmeticError.itemNotInCatalog` for unknown slugs,
    /// `CosmeticError.alreadyOwned` for duplicate purchases, or an
    /// `EconomyError` if the player can't afford it.
    func purchase(slug: String, in context: ModelContext) throws

    /// Mark this item as equipped in its slot, un-equipping any other item of
    /// the same kind.
    func equip(_ cosmetic: DBModel.OwnedCosmetic, in context: ModelContext)

    /// Remove this item from its equipped slot.
    func unequip(_ cosmetic: DBModel.OwnedCosmetic, in context: ModelContext)

    /// Return the currently equipped item for the given kind, if any.
    func equipped(kind: CosmeticKind, in context: ModelContext) -> DBModel.OwnedCosmetic?
}

final class RealCosmeticInteractor: CosmeticInteractor {

    private let economy: EconomyInteractor
    private let achievements: AchievementInteractor

    init(
        economy: EconomyInteractor = RealEconomyInteractor(),
        achievements: AchievementInteractor = StubAchievementInteractor()
    ) {
        self.economy = economy
        self.achievements = achievements
    }

    func purchase(slug: String, in context: ModelContext) throws {
        guard let catalogItem = CosmeticCatalog.item(slug: slug) else {
            throw CosmeticError.itemNotInCatalog
        }
        let allOwned = (try? context.fetch(FetchDescriptor<DBModel.OwnedCosmetic>())) ?? []
        guard !allOwned.contains(where: { $0.slug == slug }) else {
            throw CosmeticError.alreadyOwned
        }
        try economy.spend(catalogItem.goldCost, reason: "cosmetic-\(slug)", in: context)
        context.insert(DBModel.OwnedCosmetic(slug: slug, kind: catalogItem.kind))
        achievements.checkAll(in: context)
        context.saveQuietly()
    }

    func equip(_ cosmetic: DBModel.OwnedCosmetic, in context: ModelContext) {
        let allOwned = (try? context.fetch(FetchDescriptor<DBModel.OwnedCosmetic>())) ?? []
        for other in allOwned where other.kind == cosmetic.kind && other.id != cosmetic.id {
            other.equippedAt = nil
            other.updatedAt = Date()
        }
        cosmetic.equippedAt = Date()
        cosmetic.updatedAt = Date()
        context.saveQuietly()
    }

    func unequip(_ cosmetic: DBModel.OwnedCosmetic, in context: ModelContext) {
        cosmetic.equippedAt = nil
        cosmetic.updatedAt = Date()
        context.saveQuietly()
    }

    func equipped(kind: CosmeticKind, in context: ModelContext) -> DBModel.OwnedCosmetic? {
        let all = (try? context.fetch(FetchDescriptor<DBModel.OwnedCosmetic>())) ?? []
        return all.first { $0.kind == kind && $0.equippedAt != nil }
    }
}

final class StubCosmeticInteractor: CosmeticInteractor {
    func purchase(slug: String, in context: ModelContext) throws {}
    func equip(_ cosmetic: DBModel.OwnedCosmetic, in context: ModelContext) {}
    func unequip(_ cosmetic: DBModel.OwnedCosmetic, in context: ModelContext) {}
    func equipped(kind: CosmeticKind, in context: ModelContext) -> DBModel.OwnedCosmetic? { nil }
}

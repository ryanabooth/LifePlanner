import Foundation
import SwiftData

enum CosmeticKind: Int, Codable, CaseIterable, Identifiable {
    case hat = 0
    case outfit = 1
    case pet = 2
    case farmhouseDecor = 3

    var id: Int { rawValue }

    var pickerLabel: String {
        switch self {
        case .hat:           "Hats"
        case .outfit:        "Outfits"
        case .pet:           "Pets"
        case .farmhouseDecor:"House"
        }
    }

    var icon: String {
        switch self {
        case .hat:           "🎩"
        case .outfit:        "👕"
        case .pet:           "🐾"
        case .farmhouseDecor:"🏠"
        }
    }
}

extension DBModel {
    /// One row per cosmetic item the player has purchased. The `equippedAt`
    /// timestamp doubles as the equipped flag — nil means unequipped. Only one
    /// row per `kind` should have a non-nil `equippedAt` at a time;
    /// `CosmeticInteractor.equip(_:)` enforces this invariant.
    @Model
    final class OwnedCosmetic {
        var id: UUID = UUID()
        /// Matches a `CosmeticCatalogItem.slug`. Stable across app versions.
        var slug: String = ""
        var kind: CosmeticKind = CosmeticKind.hat
        /// Non-nil while this item is the active equipped choice for its kind.
        var equippedAt: Date? = nil
        var acquiredAt: Date = Date()
        var updatedAt: Date = Date()

        init(
            id: UUID = UUID(),
            slug: String = "",
            kind: CosmeticKind = .hat,
            equippedAt: Date? = nil,
            acquiredAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.slug = slug
            self.kind = kind
            self.equippedAt = equippedAt
            self.acquiredAt = acquiredAt
            self.updatedAt = updatedAt
        }
    }
}

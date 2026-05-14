import Foundation

/// A single purchasable item from the cosmetic shop. The full catalog is
/// code-defined here so content updates land without schema migrations.
struct CosmeticCatalogItem: Identifiable {
    let slug: String
    let kind: CosmeticKind
    let name: String
    let description: String
    let goldCost: Int

    var id: String { slug }
}

/// Complete catalog of every cosmetic item in the game. Phase 2 art lands by
/// adding imagesets named `cosmetic_<slug>` to `Assets.xcassets` — no code
/// change needed per item.
enum CosmeticCatalog {

    static let all: [CosmeticCatalogItem] = hats + outfits + pets + farmhouse

    static let hats: [CosmeticCatalogItem] = [
        .init(slug: "hat_cap",    kind: .hat, name: "Baseball Cap",
              description: "Classic and comfy.",            goldCost: 15),
        .init(slug: "hat_sunhat", kind: .hat, name: "Sun Hat",
              description: "Wide brim for sunny days.",     goldCost: 20),
        .init(slug: "hat_tophat", kind: .hat, name: "Top Hat",
              description: "Dapper and distinguished.",     goldCost: 40),
    ]

    static let outfits: [CosmeticCatalogItem] = [
        .init(slug: "outfit_overalls", kind: .outfit, name: "Overalls",
              description: "Classic farmer style.",         goldCost: 25),
        .init(slug: "outfit_plaid",    kind: .outfit, name: "Plaid Shirt",
              description: "Warm and rugged.",              goldCost: 30),
        .init(slug: "outfit_formal",   kind: .outfit, name: "Formal Wear",
              description: "Farming in style.",             goldCost: 50),
    ]

    static let pets: [CosmeticCatalogItem] = [
        .init(slug: "pet_cat",   kind: .pet, name: "Cat",
              description: "Wanders on its own schedule.", goldCost: 25),
        .init(slug: "pet_dog",   kind: .pet, name: "Dog",
              description: "A loyal farm companion.",      goldCost: 30),
        .init(slug: "pet_sheep", kind: .pet, name: "Sheep",
              description: "Fluffy and friendly.",         goldCost: 35),
    ]

    static let farmhouse: [CosmeticCatalogItem] = [
        .init(slug: "house_flower_box", kind: .farmhouseDecor, name: "Flower Boxes",
              description: "Cheerful window boxes.",       goldCost: 20),
        .init(slug: "house_red_roof",   kind: .farmhouseDecor, name: "Red Roof",
              description: "A classic barn-red roof.",     goldCost: 40),
        .init(slug: "house_blue_roof",  kind: .farmhouseDecor, name: "Blue Roof",
              description: "A cool sky-blue roof.",        goldCost: 40),
    ]

    static func item(slug: String) -> CosmeticCatalogItem? {
        all.first { $0.slug == slug }
    }
}

import Foundation

/// Stable names for farm sprite assets. The scene looks every texture up by one
/// of these keys; if `UIImage(named:)` finds an `Assets.xcassets` imageset with
/// the matching name, it's used. Otherwise `PlotTextureFactory` falls back to
/// procedural placeholders.
///
/// Phase 2 will populate Assets.xcassets with imagesets named per these keys.
/// Until then, every key resolves to a procedural placeholder.
enum AssetKeys {

    static func plot(_ kind: FarmElementType, state: PlotState) -> String {
        "plot_\(kind.assetSlug)_\(state.assetSlug)"
    }

    enum HUD {
        static let goldIcon = "hud_gold_icon"
    }
}

extension FarmElementType {
    var assetSlug: String {
        switch self {
        case .crop: return "crop"
        case .animal: return "animal"
        case .tree: return "tree"
        case .structure: return "structure"
        case .commonField: return "common_field"
        }
    }
}

extension PlotState {
    var assetSlug: String {
        switch self {
        case .empty: return "empty"
        case .growing: return "growing"
        case .mature: return "mature"
        case .withered: return "withered"
        case .dead: return "dead"
        }
    }
}

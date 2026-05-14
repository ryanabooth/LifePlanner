import SpriteKit
import UIKit

/// Single point of texture lookup for farm plot sprites. Resolution order:
/// 1. `UIImage(named:)` against `Assets.xcassets` using the `AssetKeys.plot`
///    name — used once Phase 2's AI-generated artwork lands.
/// 2. Procedural fallback drawn here as a colored shape + emoji glyph so the
///    farm is fully playable without any imported art.
///
/// Adding new art is asset-only: drop an imageset named e.g. `plot_crop_mature`
/// into Assets.xcassets and the factory picks it up — no code change required.
enum PlotTextureFactory {

    static func texture(for kind: FarmElementType, state: PlotState, size: CGFloat) -> SKTexture {
        let key = AssetKeys.plot(kind, state: state)
        if let image = UIImage(named: key) {
            return SKTexture(image: image)
        }
        return placeholder(for: kind, state: state, size: size)
    }

    // MARK: - Procedural placeholder

    private static func placeholder(for kind: FarmElementType, state: PlotState, size: CGFloat) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            let cgCtx = ctx.cgContext
            let rect = CGRect(x: 0, y: 0, width: size, height: size)

            // Base tile with rounded corners.
            let baseColor = baseFill(for: kind).adjusted(for: state)
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 12)
            baseColor.setFill()
            path.fill()

            // Glyph in the middle so the kind is identifiable without text.
            let glyph = glyph(for: kind, state: state)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.55),
                .foregroundColor: UIColor.white.withAlphaComponent(state == .dead ? 0.4 : 0.95)
            ]
            let glyphString = NSAttributedString(string: glyph, attributes: attrs)
            let textSize = glyphString.size()
            let textPoint = CGPoint(
                x: (size - textSize.width) / 2,
                y: (size - textSize.height) / 2
            )
            glyphString.draw(at: textPoint)

            // Dead overlay: a stark X so withered/dead are visually distinct.
            if state == .dead {
                cgCtx.setStrokeColor(UIColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 1).cgColor)
                cgCtx.setLineWidth(size * 0.05)
                cgCtx.move(to: CGPoint(x: size * 0.2, y: size * 0.2))
                cgCtx.addLine(to: CGPoint(x: size * 0.8, y: size * 0.8))
                cgCtx.move(to: CGPoint(x: size * 0.8, y: size * 0.2))
                cgCtx.addLine(to: CGPoint(x: size * 0.2, y: size * 0.8))
                cgCtx.strokePath()
            }
        }
        return SKTexture(image: image)
    }

    private static func baseFill(for kind: FarmElementType) -> UIColor {
        switch kind {
        case .crop:         return UIColor(red: 0.42, green: 0.78, blue: 0.32, alpha: 1)
        case .animal:       return UIColor(red: 0.85, green: 0.65, blue: 0.40, alpha: 1)
        case .tree:         return UIColor(red: 0.22, green: 0.55, blue: 0.30, alpha: 1)
        case .structure:    return UIColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1)
        case .commonField:  return UIColor(red: 0.78, green: 0.72, blue: 0.40, alpha: 1)
        }
    }

    private static func glyph(for kind: FarmElementType, state: PlotState) -> String {
        if state == .dead { return "✖" }
        if state == .withered { return "💧" }
        switch kind {
        case .crop:         return "🌾"
        case .animal:       return "🐄"
        case .tree:         return "🌳"
        case .structure:    return "🏠"
        case .commonField:  return "🌼"
        }
    }
}

private extension UIColor {
    /// Desaturate / darken for withered or dead states so glyph + tint sell the
    /// health story before any animation lands.
    func adjusted(for state: PlotState) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        switch state {
        case .withered:
            return UIColor(hue: hue, saturation: saturation * 0.4, brightness: brightness * 0.85, alpha: alpha)
        case .dead:
            return UIColor(hue: hue, saturation: saturation * 0.2, brightness: brightness * 0.55, alpha: alpha)
        default:
            return self
        }
    }
}

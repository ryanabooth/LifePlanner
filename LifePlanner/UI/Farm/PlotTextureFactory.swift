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
            let half = size / 2
            let inset: CGFloat = 4

            // Diamond path clipped so the placeholder matches the PNG tile shape.
            let diamond = UIBezierPath()
            diamond.move(to:    CGPoint(x: half,        y: inset))
            diamond.addLine(to: CGPoint(x: size - inset, y: half))
            diamond.addLine(to: CGPoint(x: half,        y: size - inset))
            diamond.addLine(to: CGPoint(x: inset,       y: half))
            diamond.close()

            let baseColor = baseFill(for: kind).adjusted(for: state)
            baseColor.setFill()
            diamond.fill()

            // Subtle darker border.
            baseColor.withAlphaComponent(0.5).setStroke()
            diamond.lineWidth = 2
            diamond.stroke()

            // Glyph centred in the diamond.
            let glyph = glyph(for: kind, state: state)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.38),
                .foregroundColor: UIColor.white.withAlphaComponent(state == .dead ? 0.4 : 0.95)
            ]
            let glyphStr  = NSAttributedString(string: glyph, attributes: attrs)
            let glyphSize = glyphStr.size()
            glyphStr.draw(at: CGPoint(x: (size - glyphSize.width) / 2,
                                      y: (size - glyphSize.height) / 2))

            // Dead X overlay.
            if state == .dead {
                cgCtx.setStrokeColor(UIColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 0.8).cgColor)
                cgCtx.setLineWidth(size * 0.05)
                cgCtx.move(to: CGPoint(x: size * 0.3, y: size * 0.3))
                cgCtx.addLine(to: CGPoint(x: size * 0.7, y: size * 0.7))
                cgCtx.move(to: CGPoint(x: size * 0.7, y: size * 0.3))
                cgCtx.addLine(to: CGPoint(x: size * 0.3, y: size * 0.7))
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

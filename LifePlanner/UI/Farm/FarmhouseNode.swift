import SpriteKit

/// Farmhouse landmark placed in the upper portion of the scene. Renders
/// artwork from `Assets.xcassets` keyed by the equipped `farmhouseDecor`
/// cosmetic slug (see `AssetKeys.farmhouse`) — `house_default`,
/// `house_red_roof`, `house_blue_roof`, or `house_flower_box` — falling back
/// to a procedural placeholder if the imageset is missing, same pattern as
/// `PlotTextureFactory`.
final class FarmhouseNode: SKNode {

    private static let displaySize = CGSize(width: 160, height: 160)

    private let sprite: SKSpriteNode

    override init() {
        sprite = SKSpriteNode(texture: Self.texture(for: nil), size: Self.displaySize)
        // Anchor the sprite's bottom edge at the node's local origin, matching
        // where the old procedural building's base sat, so `FarmScene`'s
        // existing `layoutFarmhouse()` positioning still reads correctly.
        sprite.position = CGPoint(x: 0, y: Self.displaySize.height / 2)
        super.init()
        addChild(sprite)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    func applyDecor(slug: String?) {
        sprite.texture = Self.texture(for: slug)
    }

    // MARK: - Texture lookup

    private static func texture(for slug: String?) -> SKTexture {
        let key = AssetKeys.farmhouse(slug: slug)
        if let image = UIImage(named: key) {
            return SKTexture(image: image)
        }
        return placeholder(for: slug)
    }

    // MARK: - Procedural placeholder

    private static func placeholder(for slug: String?) -> SKTexture {
        let size = displaySize
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let wallRect = CGRect(x: size.width * 0.19, y: 0, width: size.width * 0.62, height: size.height * 0.42)
            UIColor(white: 0.72, alpha: 1).setFill()
            UIBezierPath(rect: wallRect).fill()

            let doorRect = CGRect(x: size.width * 0.42, y: 0, width: size.width * 0.16, height: size.height * 0.25)
            UIColor(red: 0.45, green: 0.25, blue: 0.10, alpha: 1).setFill()
            UIBezierPath(rect: doorRect).fill()

            for xFraction: CGFloat in [0.24, 0.60] {
                let winRect = CGRect(
                    x: size.width * xFraction, y: size.height * 0.16,
                    width: size.width * 0.12, height: size.height * 0.12
                )
                UIColor(red: 0.95, green: 0.75, blue: 0.30, alpha: 0.9).setFill()
                UIBezierPath(rect: winRect).fill()
            }

            let roofPath = UIBezierPath()
            roofPath.move(to: CGPoint(x: size.width * 0.10, y: size.height * 0.42))
            roofPath.addLine(to: CGPoint(x: size.width * 0.50, y: size.height * 0.90))
            roofPath.addLine(to: CGPoint(x: size.width * 0.90, y: size.height * 0.42))
            roofPath.close()
            roofColor(for: slug).setFill()
            roofPath.fill()

            if slug == "house_flower_box" {
                let colors: [UIColor] = [
                    UIColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1),
                    UIColor(red: 1.00, green: 0.80, blue: 0.10, alpha: 1),
                    UIColor(red: 0.85, green: 0.40, blue: 0.85, alpha: 1),
                ]
                for (i, color) in colors.enumerated() {
                    let x = wallRect.minX + wallRect.width * (CGFloat(i) + 0.5) / CGFloat(colors.count)
                    let flower = UIBezierPath(
                        ovalIn: CGRect(x: x - size.width * 0.02, y: size.height * 0.02, width: size.width * 0.04, height: size.width * 0.04)
                    )
                    color.setFill()
                    flower.fill()
                }
            }
        }
        return SKTexture(image: image)
    }

    private static func roofColor(for slug: String?) -> UIColor {
        switch slug {
        case "house_red_roof", "house_flower_box":
            return UIColor(red: 0.72, green: 0.18, blue: 0.12, alpha: 1)
        case "house_blue_roof":
            return UIColor(red: 0.20, green: 0.45, blue: 0.78, alpha: 1)
        default:
            return UIColor(white: 0.55, alpha: 1)
        }
    }
}

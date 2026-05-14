import SpriteKit

/// Static farmhouse decoration placed in the upper portion of the scene.
/// Procedural placeholder; roof color and flower boxes change with the
/// equipped farmhouse cosmetic. Phase 2 art swaps in via `Assets.xcassets`.
final class FarmhouseNode: SKNode {

    private var roofNode: SKShapeNode?
    private var flowerBoxNode: SKNode?

    override init() {
        super.init()
        buildBase()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    func applyDecor(slug: String?) {
        roofNode?.fillColor = roofColor(for: slug)

        flowerBoxNode?.removeFromParent()
        flowerBoxNode = nil
        if slug == "house_flower_box" {
            let fb = makeFlowerBox()
            addChild(fb)
            flowerBoxNode = fb
        }
    }

    // MARK: - Build

    private func buildBase() {
        // Walls
        let walls = SKShapeNode(rect: CGRect(x: -30, y: 0, width: 60, height: 40))
        walls.fillColor = UIColor(red: 0.85, green: 0.80, blue: 0.72, alpha: 1)
        walls.strokeColor = UIColor(white: 0.5, alpha: 0.4)
        walls.lineWidth = 1
        addChild(walls)

        // Door
        let door = SKShapeNode(rect: CGRect(x: -8, y: 0, width: 16, height: 24))
        door.fillColor = UIColor(red: 0.45, green: 0.25, blue: 0.10, alpha: 1)
        door.strokeColor = .clear
        addChild(door)

        // Windows
        for x: CGFloat in [-24, 12] {
            let win = SKShapeNode(rect: CGRect(x: x, y: 16, width: 12, height: 12))
            win.fillColor = UIColor(red: 0.60, green: 0.82, blue: 0.95, alpha: 0.8)
            win.strokeColor = UIColor(white: 0.5, alpha: 0.5)
            win.lineWidth = 1
            addChild(win)
        }

        // Roof (default grey until a decor is equipped)
        let roofPath = CGMutablePath()
        roofPath.move(to: CGPoint(x: -38, y: 40))
        roofPath.addLine(to: CGPoint(x: 0, y: 70))
        roofPath.addLine(to: CGPoint(x: 38, y: 40))
        roofPath.closeSubpath()
        let roof = SKShapeNode(path: roofPath)
        roof.fillColor = roofColor(for: nil)
        roof.strokeColor = .clear
        addChild(roof)
        roofNode = roof
    }

    private func makeFlowerBox() -> SKNode {
        let box = SKNode()

        let plank = SKShapeNode(rect: CGRect(x: -32, y: -6, width: 64, height: 8))
        plank.fillColor = UIColor(red: 0.45, green: 0.25, blue: 0.10, alpha: 1)
        plank.strokeColor = .clear
        box.addChild(plank)

        let colors: [UIColor] = [
            UIColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1),
            UIColor(red: 1.00, green: 0.80, blue: 0.10, alpha: 1),
            UIColor(red: 0.85, green: 0.40, blue: 0.85, alpha: 1),
            UIColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1),
        ]
        let xs: [CGFloat] = [-22, -8, 8, 22]
        for (x, color) in zip(xs, colors) {
            let flower = SKShapeNode(circleOfRadius: 4)
            flower.fillColor = color
            flower.strokeColor = .clear
            flower.position = CGPoint(x: x, y: 6)
            box.addChild(flower)
        }

        box.position = CGPoint(x: 0, y: 40)
        return box
    }

    private func roofColor(for slug: String?) -> UIColor {
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

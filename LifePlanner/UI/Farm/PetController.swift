import SpriteKit

/// Unlockable pet companion that wanders the farm. Procedural placeholder
/// sprites; swaps to art-backed textures when Phase 2 assets land.
/// Showing/hiding the pet is driven by `applyCosmetics(petSlug:)`.
final class PetController {

    private let container = SKNode()
    private weak var parentScene: SKScene?
    private var petNode: SKNode?

    private static let zLayer: CGFloat = 0.5

    func populate(in scene: SKScene) {
        parentScene = scene
        container.removeFromParent()
        container.removeAllChildren()
        container.zPosition = Self.zLayer
        scene.addChild(container)
    }

    func applyCosmetics(petSlug: String?) {
        petNode?.removeFromParent()
        petNode = nil
        guard let slug = petSlug, let scene = parentScene else { return }
        let pet = makePet(slug: slug, in: scene)
        container.addChild(pet)
        petNode = pet
    }

    // MARK: - Pet sprites

    private func makePet(slug: String, in scene: SKScene) -> SKNode {
        let node = SKNode()
        switch slug {
        case "pet_sheep": buildSheep(on: node)
        case "pet_cat":   buildCat(on: node)
        default:          buildDog(on: node)          // "pet_dog"
        }

        // Gentle idle bob.
        let up = SKAction.moveBy(x: 0, y: 2, duration: 0.6)
        up.timingMode = .easeInEaseOut
        node.run(SKAction.repeatForever(SKAction.sequence([up, up.reversed()])), withKey: "bob")

        node.position = randomPosition(in: scene)
        node.run(wanderAction(), withKey: "wander")
        return node
    }

    private func buildSheep(on node: SKNode) {
        let body = SKShapeNode(circleOfRadius: 14)
        body.fillColor = UIColor(white: 0.95, alpha: 1)
        body.strokeColor = .clear
        node.addChild(body)

        for offset in [CGPoint(x: -10, y: 6), CGPoint(x: 10, y: 6), CGPoint(x: 0, y: 14)] {
            let tuft = SKShapeNode(circleOfRadius: 8)
            tuft.fillColor = UIColor(white: 0.90, alpha: 1)
            tuft.strokeColor = .clear
            tuft.position = offset
            node.addChild(tuft)
        }

        for legX: CGFloat in [-6, 6] {
            let leg = SKShapeNode(rect: CGRect(x: -2, y: -18, width: 4, height: 8))
            leg.fillColor = UIColor(white: 0.80, alpha: 1)
            leg.strokeColor = .clear
            leg.position = CGPoint(x: legX, y: 0)
            node.addChild(leg)
        }
    }

    private func buildCat(on node: SKNode) {
        let orange = UIColor(red: 0.85, green: 0.50, blue: 0.15, alpha: 1)

        let body = SKShapeNode(ellipseOf: CGSize(width: 20, height: 14))
        body.fillColor = orange
        body.strokeColor = .clear
        node.addChild(body)

        let head = SKShapeNode(circleOfRadius: 9)
        head.fillColor = orange
        head.strokeColor = .clear
        head.position = CGPoint(x: 10, y: 5)
        node.addChild(head)

        for (ex, rot): (CGFloat, CGFloat) in [(5, -0.4), (15, 0.4)] {
            let earPath = CGMutablePath()
            earPath.move(to: .zero)
            earPath.addLine(to: CGPoint(x: -4, y: 8))
            earPath.addLine(to: CGPoint(x: 4, y: 8))
            earPath.closeSubpath()
            let ear = SKShapeNode(path: earPath)
            ear.fillColor = UIColor(red: 0.75, green: 0.40, blue: 0.10, alpha: 1)
            ear.strokeColor = .clear
            ear.position = CGPoint(x: ex, y: 12)
            ear.zRotation = rot
            node.addChild(ear)
        }
    }

    private func buildDog(on node: SKNode) {
        let brown = UIColor(red: 0.55, green: 0.32, blue: 0.10, alpha: 1)

        let body = SKShapeNode(ellipseOf: CGSize(width: 22, height: 14))
        body.fillColor = brown
        body.strokeColor = .clear
        node.addChild(body)

        let head = SKShapeNode(circleOfRadius: 10)
        head.fillColor = brown
        head.strokeColor = .clear
        head.position = CGPoint(x: 12, y: 4)
        node.addChild(head)

        let snout = SKShapeNode(ellipseOf: CGSize(width: 8, height: 6))
        snout.fillColor = UIColor(red: 0.70, green: 0.50, blue: 0.35, alpha: 1)
        snout.strokeColor = .clear
        snout.position = CGPoint(x: 20, y: 1)
        node.addChild(snout)

        let ear = SKShapeNode(ellipseOf: CGSize(width: 8, height: 14))
        ear.fillColor = UIColor(red: 0.40, green: 0.22, blue: 0.07, alpha: 1)
        ear.strokeColor = .clear
        ear.position = CGPoint(x: 12, y: 12)
        node.addChild(ear)
    }

    // MARK: - Wandering

    private func wanderAction() -> SKAction {
        let step = SKAction.customAction(withDuration: 0) { [weak self] node, _ in
            guard
                let self,
                let scene = self.parentScene,
                node.action(forKey: "wander-move") == nil
            else { return }
            let target = self.randomPosition(in: scene)
            let distance = hypot(target.x - node.position.x, target.y - node.position.y)
            let duration = max(2.0, distance / 20.0) * Double.random(in: 0.9...1.3)
            let move = SKAction.move(to: target, duration: duration)
            move.timingMode = .easeInEaseOut
            node.run(move, withKey: "wander-move")
            node.xScale = target.x < node.position.x ? -1 : 1
        }
        return SKAction.repeatForever(SKAction.sequence([step, SKAction.wait(forDuration: 0.25)]))
    }

    private func randomPosition(in scene: SKScene) -> CGPoint {
        let margin: CGFloat = 30
        let x = CGFloat.random(in: margin...max(margin + 1, scene.size.width - margin))
        let y = scene.size.height * CGFloat.random(in: 0.22...0.44)
        return CGPoint(x: x, y: y)
    }
}

import SpriteKit

/// The farmer avatar — a procedural character that wanders the mid-level of
/// the farm scene. Hat and outfit visuals respond to equipped cosmetics.
/// Follows the same populate/wander pattern as `AmbientLifeController`.
final class AvatarController {

    private let container = SKNode()
    private weak var parentScene: SKScene?

    private var bodyNode: SKShapeNode?
    private var hatNode: SKNode?

    /// In front of ambient life (z -1) and plots (z 0); below HUD overlays.
    private static let zLayer: CGFloat = 1.0

    func populate(in scene: SKScene) {
        parentScene = scene
        container.removeFromParent()
        container.removeAllChildren()
        container.zPosition = Self.zLayer
        scene.addChild(container)
        buildAvatar()
        container.position = randomPosition(in: scene)
        container.run(wanderAction(), withKey: "wander")
    }

    func applyCosmetics(hatSlug: String?, outfitSlug: String?) {
        bodyNode?.fillColor = outfitColor(for: outfitSlug)
        hatNode?.removeFromParent()
        hatNode = nil
        if let slug = hatSlug {
            let hat = makeHat(slug: slug)
            container.addChild(hat)
            hatNode = hat
        }
    }

    // MARK: - Build

    private func buildAvatar() {
        let body = SKShapeNode(ellipseOf: CGSize(width: 16, height: 20))
        body.fillColor = outfitColor(for: nil)
        body.strokeColor = .clear
        container.addChild(body)
        bodyNode = body

        let head = SKShapeNode(circleOfRadius: 8)
        head.fillColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.70, green: 0.55, blue: 0.42, alpha: 1)
                : UIColor(red: 0.95, green: 0.80, blue: 0.65, alpha: 1)
        }
        head.strokeColor = .clear
        head.position = CGPoint(x: 0, y: 18)
        container.addChild(head)

        // Gentle idle bob.
        let up = SKAction.moveBy(x: 0, y: 3, duration: 0.5)
        up.timingMode = .easeInEaseOut
        container.run(SKAction.repeatForever(SKAction.sequence([up, up.reversed()])), withKey: "bob")
    }

    private func makeHat(slug: String) -> SKNode {
        let node = SKNode()
        let color = hatColor(for: slug)

        // Brim
        let brim = SKShapeNode(rect: CGRect(x: -10, y: 0, width: 20, height: 3))
        brim.fillColor = color
        brim.strokeColor = .clear
        node.addChild(brim)

        // Crown
        let crown = SKShapeNode(rect: CGRect(x: -7, y: 3, width: 14, height: 8))
        crown.fillColor = color
        crown.strokeColor = .clear
        node.addChild(crown)

        node.position = CGPoint(x: 0, y: 23)
        return node
    }

    private func hatColor(for slug: String) -> UIColor {
        switch slug {
        case "hat_cap":
            return UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.40, green: 0.60, blue: 1.00, alpha: 1)
                    : UIColor(red: 0.25, green: 0.45, blue: 0.80, alpha: 1)
            }
        case "hat_sunhat":
            return UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 1.00, green: 0.88, blue: 0.45, alpha: 1)
                    : UIColor(red: 0.87, green: 0.72, blue: 0.35, alpha: 1)
            }
        case "hat_tophat":
            return UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1)
                    : UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
            }
        default:
            return UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.70, green: 0.45, blue: 0.18, alpha: 1)
                    : UIColor(red: 0.50, green: 0.30, blue: 0.10, alpha: 1)
            }
        }
    }

    private func outfitColor(for slug: String?) -> UIColor {
        switch slug {
        case "outfit_overalls":
            return UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.40, green: 0.55, blue: 0.95, alpha: 1)
                    : UIColor(red: 0.25, green: 0.40, blue: 0.75, alpha: 1)
            }
        case "outfit_plaid":
            return UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.80, green: 0.30, blue: 0.30, alpha: 1)
                    : UIColor(red: 0.65, green: 0.20, blue: 0.20, alpha: 1)
            }
        case "outfit_formal":
            return UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.20, green: 0.20, blue: 0.55, alpha: 1)
                    : UIColor(red: 0.10, green: 0.10, blue: 0.35, alpha: 1)
            }
        default:
            return UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.55, green: 0.32, blue: 0.14, alpha: 1)
                    : UIColor(red: 0.36, green: 0.20, blue: 0.09, alpha: 1)
            }
        }
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
            let duration = max(2.0, distance / 25.0) * Double.random(in: 0.8...1.2)
            let move = SKAction.move(to: target, duration: duration)
            move.timingMode = .easeInEaseOut
            node.run(move, withKey: "wander-move")
            node.xScale = target.x < node.position.x ? -1 : 1
        }
        return SKAction.repeatForever(SKAction.sequence([step, SKAction.wait(forDuration: 0.25)]))
    }

    private func randomPosition(in scene: SKScene) -> CGPoint {
        let margin: CGFloat = 40
        let x = CGFloat.random(in: margin...max(margin + 1, scene.size.width - margin))
        let y = scene.size.height * CGFloat.random(in: 0.28...0.48)
        return CGPoint(x: x, y: y)
    }
}

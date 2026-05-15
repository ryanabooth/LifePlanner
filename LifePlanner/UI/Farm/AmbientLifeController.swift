import SpriteKit

/// Pure-flavor wildlife wandering the farm background — butterflies fluttering
/// near the plots and a bird or two drifting across the sky. No interaction,
/// no model coupling. Cheap procedural sprites so we ship without art.
///
/// FarmScene owns one of these and calls `populate(in:)` once after `didMove`.
/// Each creature schedules its own wander loop via SKAction; the controller
/// just holds a strong ref to the parent container so it can lay them out and
/// re-target them on resize.
final class AmbientLifeController {

    /// Container layer that lives behind the plots but in front of the
    /// background color. Set up by `populate(in:)`.
    private let container = SKNode()
    private weak var parentScene: SKScene?

    private let butterflyCount = 3
    private let birdCount = 1

    /// Z-position for ambient life — between the green background (0) and the
    /// plot nodes (default zPosition higher in the scene).
    private static let zBackground: CGFloat = -1

    func populate(in scene: SKScene) {
        parentScene = scene
        container.removeFromParent()
        container.removeAllChildren()
        container.zPosition = Self.zBackground
        scene.addChild(container)

        for _ in 0..<butterflyCount {
            container.addChild(makeButterfly(in: scene))
        }
        for _ in 0..<birdCount {
            container.addChild(makeBird(in: scene))
        }
    }

    /// Re-target wandering bounds when the scene resizes. Existing creatures
    /// keep their current positions; their next wander pick will use the new
    /// bounds.
    func refreshBounds() {
        // No persistent bounds state — each creature reads `parentScene?.size`
        // when scheduling its next move, so nothing to do here. Method exists
        // so FarmScene has a stable hook in case we cache bounds later.
    }

    // MARK: - Butterfly

    private func makeButterfly(in scene: SKScene) -> SKNode {
        let butterfly = SKNode()
        butterfly.zPosition = Self.zBackground

        // Two ~8 pt colored ovals as wings. Stored on the node so the flap
        // action can scale them independently of the body.
        let palette: [UIColor] = [
            UIColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 0.85), // amber
            UIColor(red: 0.95, green: 0.55, blue: 0.70, alpha: 0.85), // pink
            UIColor(red: 0.55, green: 0.40, blue: 0.95, alpha: 0.85)  // violet
        ]
        let color = palette.randomElement() ?? palette[0]

        let leftWing = SKShapeNode(ellipseOf: CGSize(width: 9, height: 6))
        leftWing.fillColor = color
        leftWing.strokeColor = .clear
        leftWing.position = CGPoint(x: -4, y: 0)
        butterfly.addChild(leftWing)

        let rightWing = SKShapeNode(ellipseOf: CGSize(width: 9, height: 6))
        rightWing.fillColor = color
        rightWing.strokeColor = .clear
        rightWing.position = CGPoint(x: 4, y: 0)
        butterfly.addChild(rightWing)

        // Wing flap: scale Y axis 1.0 -> 0.4 and back, ~5 Hz.
        if !UIAccessibility.isReduceMotionEnabled {
            let flapDown = SKAction.scaleY(to: 0.4, duration: 0.10)
            let flapUp = SKAction.scaleY(to: 1.0, duration: 0.10)
            let flap = SKAction.repeatForever(SKAction.sequence([flapDown, flapUp]))
            leftWing.run(flap)
            rightWing.run(flap)
        }

        // Start in a random spot near the plot row vertical zone.
        butterfly.position = randomPosition(
            in: scene,
            yRange: 0.25...0.55
        )
        butterfly.run(wanderAction(yRange: 0.25...0.55), withKey: "wander")
        return butterfly
    }

    // MARK: - Bird

    private func makeBird(in scene: SKScene) -> SKNode {
        let bird = SKNode()
        bird.zPosition = Self.zBackground

        // Bird body: a small dark V (two strokes meeting at the bottom). 12 pt
        // wide; the V flaps by widening/narrowing.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -6, y: 3))
        path.addLine(to: CGPoint(x: 0, y: -2))
        path.addLine(to: CGPoint(x: 6, y: 3))
        let shape = SKShapeNode(path: path)
        shape.strokeColor = UIColor(white: 0.2, alpha: 0.7)
        shape.lineWidth = 2
        shape.lineCap = .round
        shape.lineJoin = .round
        bird.addChild(shape)

        // Slow horizontal flap to feel like wing-beats.
        if !UIAccessibility.isReduceMotionEnabled {
            let widen = SKAction.scaleX(to: 1.2, duration: 0.35)
            let narrow = SKAction.scaleX(to: 0.85, duration: 0.35)
            shape.run(SKAction.repeatForever(SKAction.sequence([widen, narrow])))
        }

        // Birds live higher up.
        bird.position = randomPosition(in: scene, yRange: 0.70...0.92)
        bird.run(wanderAction(yRange: 0.70...0.92), withKey: "wander")
        return bird
    }

    // MARK: - Wandering

    /// Repeating move-to-random-point loop. Re-evaluates the scene size on each
    /// pick so resizes are naturally accommodated.
    private func wanderAction(yRange: ClosedRange<CGFloat>) -> SKAction {
        let step = SKAction.customAction(withDuration: 0) { [weak self] node, _ in
            guard
                let self,
                let scene = self.parentScene,
                node.action(forKey: "wander-move") == nil
            else { return }
            let target = self.randomPosition(in: scene, yRange: yRange)
            let distance = hypot(target.x - node.position.x, target.y - node.position.y)
            // Speed ~30 pt/s with a little jitter so creatures don't sync.
            let baseSpeed: CGFloat = 30
            let duration = max(1.5, distance / baseSpeed) * Double.random(in: 0.8...1.4)
            let move = SKAction.move(to: target, duration: duration)
            move.timingMode = .easeInEaseOut
            node.run(move, withKey: "wander-move")
        }
        let wait = SKAction.run { /* drained by next custom step */ }
        let tick = SKAction.wait(forDuration: 0.25)
        // Sequence: try to schedule a new target; wait briefly; loop. The
        // schedule step itself is a no-op if a move is already in flight,
        // letting movements complete before re-targeting.
        return SKAction.repeatForever(SKAction.sequence([step, wait, tick]))
    }

    private func randomPosition(in scene: SKScene, yRange: ClosedRange<CGFloat>) -> CGPoint {
        let xMargin: CGFloat = 30
        let x = CGFloat.random(in: xMargin...max(xMargin + 1, scene.size.width - xMargin))
        let y = CGFloat.random(in: yRange) * scene.size.height
        return CGPoint(x: x, y: y)
    }
}

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
    /// Separate container for seasonal particles so they can be swapped out
    /// without disturbing the permanent ambient wildlife.
    private let seasonalContainer = SKNode()
    private weak var parentScene: SKScene?

    private let butterflyCount = 3
    private let birdCount = 1

    /// Z-position for ambient life — above plot nodes (0) but below sparkles (10).
    private static let zBackground: CGFloat = 5
    /// Seasonal particles sit just above ambient life, still below sparkles.
    private static let zSeasonal: CGFloat = 6

    func populate(in scene: SKScene) {
        parentScene = scene
        container.removeFromParent()
        container.removeAllChildren()
        container.zPosition = Self.zBackground
        scene.addChild(container)

        seasonalContainer.removeFromParent()
        seasonalContainer.zPosition = Self.zSeasonal
        scene.addChild(seasonalContainer)

        for _ in 0..<butterflyCount {
            container.addChild(makeButterfly(in: scene))
        }
        for _ in 0..<birdCount {
            container.addChild(makeBird(in: scene))
        }
    }

    // MARK: - Seasonal particles

    /// Replace seasonal particle effects. Safe to call whenever the season
    /// changes. Respects Reduce Motion: clears particles but preserves the
    /// scene's background color change (handled separately in FarmScene).
    func applySeasonalEffects(_ season: Season, reduceMotion: Bool) {
        seasonalContainer.removeAllChildren()
        guard !reduceMotion, let scene = parentScene else { return }
        switch season {
        case .spring: addSpringPetals(in: scene)
        case .summer: addSummerFireflies(in: scene)
        case .fall:   addFallLeaves(in: scene)
        case .winter: addSnowflakes(in: scene)
        }
    }

    // MARK: - Spring: cherry blossom petals

    private func addSpringPetals(in scene: SKScene) {
        let petalColors: [UIColor] = [
            UIColor(red: 1.0, green: 0.75, blue: 0.80, alpha: 0.75), // blush pink
            UIColor(red: 1.0, green: 0.92, blue: 0.95, alpha: 0.70), // pale pink
            UIColor(red: 1.0, green: 0.85, blue: 0.90, alpha: 0.70), // rose white
        ]
        for i in 0..<7 {
            let petal = SKShapeNode(ellipseOf: CGSize(width: 9, height: 5))
            petal.fillColor = petalColors[i % petalColors.count]
            petal.strokeColor = .clear
            petal.zRotation = CGFloat.random(in: 0...(2 * .pi))
            let startX = CGFloat.random(in: 0...scene.size.width)
            let startY = CGFloat.random(in: 0...scene.size.height) // stagger initial positions
            petal.position = CGPoint(x: startX, y: startY)
            seasonalContainer.addChild(petal)
            startFalling(petal, in: scene,
                         speed: CGFloat.random(in: 30...55),
                         xDrift: CGFloat.random(in: 20...50) * (Bool.random() ? 1 : -1),
                         rotationRate: CGFloat.random(in: 0.5...1.5) * (Bool.random() ? 1 : -1))
        }
    }

    // MARK: - Summer: fireflies

    private func addSummerFireflies(in scene: SKScene) {
        for _ in 0..<6 {
            let fly = SKShapeNode(circleOfRadius: 3.5)
            fly.fillColor = UIColor(red: 0.85, green: 1.0, blue: 0.30, alpha: 0.85)
            fly.strokeColor = .clear
            fly.position = randomPosition(in: scene, yRange: 0.10...0.70)
            seasonalContainer.addChild(fly)
            startFireflyWander(fly, in: scene)
        }
    }

    private func startFireflyWander(_ node: SKNode, in scene: SKScene) {
        guard node.parent != nil, let scene = parentScene else { return }
        let target = randomPosition(in: scene, yRange: 0.10...0.70)
        let dist = hypot(target.x - node.position.x, target.y - node.position.y)
        let duration = max(1.5, dist / CGFloat.random(in: 18...30))
        let move = SKAction.move(to: target, duration: duration)
        move.timingMode = .easeInEaseOut
        // Pulse glow in time with movement.
        let fadeOut = SKAction.fadeAlpha(to: 0.25, duration: duration / 2)
        let fadeIn  = SKAction.fadeAlpha(to: 0.90, duration: duration / 2)
        let pulse = SKAction.sequence([fadeOut, fadeIn])
        node.run(SKAction.group([move, pulse])) { [weak self, weak node] in
            guard let node else { return }
            self?.startFireflyWander(node, in: scene)
        }
    }

    // MARK: - Fall: leaves

    private func addFallLeaves(in scene: SKScene) {
        let leafColors: [UIColor] = [
            UIColor(red: 0.85, green: 0.45, blue: 0.10, alpha: 0.80), // burnt orange
            UIColor(red: 0.75, green: 0.30, blue: 0.10, alpha: 0.75), // rust red
            UIColor(red: 0.90, green: 0.70, blue: 0.10, alpha: 0.80), // golden
        ]
        for i in 0..<6 {
            let leaf = SKShapeNode(rectOf: CGSize(width: 10, height: 7), cornerRadius: 3)
            leaf.fillColor = leafColors[i % leafColors.count]
            leaf.strokeColor = .clear
            leaf.zRotation = CGFloat.random(in: 0...(2 * .pi))
            let startX = CGFloat.random(in: 0...scene.size.width)
            let startY = CGFloat.random(in: 0...scene.size.height)
            leaf.position = CGPoint(x: startX, y: startY)
            seasonalContainer.addChild(leaf)
            startFalling(leaf, in: scene,
                         speed: CGFloat.random(in: 35...65),
                         xDrift: CGFloat.random(in: 30...70) * (Bool.random() ? 1 : -1),
                         rotationRate: CGFloat.random(in: 1.0...2.5) * (Bool.random() ? 1 : -1))
        }
    }

    // MARK: - Winter: snow

    private func addSnowflakes(in scene: SKScene) {
        for _ in 0..<10 {
            let radius = CGFloat.random(in: 2.0...4.5)
            let flake = SKShapeNode(circleOfRadius: radius)
            flake.fillColor = UIColor(white: 1.0, alpha: CGFloat.random(in: 0.55...0.80))
            flake.strokeColor = .clear
            let startX = CGFloat.random(in: 0...scene.size.width)
            let startY = CGFloat.random(in: 0...scene.size.height)
            flake.position = CGPoint(x: startX, y: startY)
            seasonalContainer.addChild(flake)
            startFalling(flake, in: scene,
                         speed: CGFloat.random(in: 20...45),
                         xDrift: CGFloat.random(in: -15...15),
                         rotationRate: 0)
        }
    }

    // MARK: - Shared falling helper

    /// Recursive: moves `node` from its current position to the bottom of the
    /// scene at `speed` pt/s, then teleports it to a random x at the top and
    /// repeats. Optionally spins the node at `rotationRate` rad/s.
    private func startFalling(_ node: SKNode, in scene: SKScene,
                              speed: CGFloat, xDrift: CGFloat, rotationRate: CGFloat) {
        guard node.parent != nil else { return }
        let remainingFall = node.position.y + 20   // distance to y = -20
        let duration = max(0.5, Double(remainingFall / speed))
        let rawX = node.position.x + xDrift * CGFloat(duration)
        let targetX = min(max(0, rawX), max(1, scene.size.width))
        let moveDown = SKAction.move(to: CGPoint(x: targetX, y: -20), duration: duration)
        let rotate = rotationRate != 0
            ? SKAction.rotate(byAngle: rotationRate * CGFloat(duration), duration: duration)
            : nil
        let group = rotate.map { SKAction.group([moveDown, $0]) } ?? moveDown
        node.run(group) { [weak self, weak node, weak scene] in
            guard let node, let scene, node.parent != nil else { return }
            node.position = CGPoint(
                x: CGFloat.random(in: 0...scene.size.width),
                y: scene.size.height + 20
            )
            self?.startFalling(node, in: scene,
                               speed: speed, xDrift: xDrift, rotationRate: rotationRate)
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
        shape.strokeColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.85, alpha: 0.7)
                : UIColor(white: 0.2, alpha: 0.7)
        }
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

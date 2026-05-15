import SpriteKit

/// Visual representation of a single `FarmPlot` in the scene. Composed of:
/// - a base sprite (texture provided by `PlotTextureFactory`)
/// - a thin health bar above the sprite (green → red as health drops)
/// - a label below showing the goal title (or "Common Field")
///
/// The associated `FarmPlot.id` is stashed on `userData` so the scene's tap
/// handling can resolve back to the model row.
///
/// Animations layered on top in Phase 2.2:
/// - Healthy plots (growing/mature) idle-sway continuously.
/// - Health increases trigger a brief scale pulse + sparkle burst.
/// - Transitioning into `.withered` plays a one-shot shake.
/// - Transitioning into `.dead` fades the sprite to a desaturated remnant.
///
/// To detect deltas the node remembers `lastHealth` and `lastState` from the
/// previous `apply(plot:)` call. The initial apply during `init` doesn't
/// animate (everything is treated as "first render").
final class PlotNode: SKNode {

    /// Size of the underlying tile in points.
    static let tileSize: CGFloat = 80

    /// The id of the corresponding `FarmPlot` row.
    private(set) var plotID: UUID

    private let sprite: SKSpriteNode
    private let healthBar: SKSpriteNode
    private let healthBarBackground: SKSpriteNode
    private let label: SKLabelNode

    /// Snapshot of the last applied health / state. Used to gate animations to
    /// real transitions rather than firing on every scene snapshot pass.
    private var lastHealth: Int
    private var lastState: PlotState

    // MARK: - SKAction keys (so we can re-trigger without stacking)
    private enum ActionKey {
        static let idle    = "idle-sway"
        static let pulse   = "contrib-pulse"
        static let shake   = "wither-shake"
        static let dissolve = "death-dissolve"
    }

    /// Called when VoiceOver double-taps the node. Set by FarmScene so the scene
    /// can publish the tappedPlotID event without coupling PlotNode to the scene.
    var onAccessibilityActivate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?()
        return true
    }

    init(plot: DBModel.FarmPlot) {
        self.plotID = plot.id
        self.lastHealth = plot.health
        self.lastState = plot.state

        let texture = PlotTextureFactory.texture(
            for: plot.kind,
            state: plot.state,
            size: Self.tileSize
        )
        self.sprite = SKSpriteNode(texture: texture, size: CGSize(width: Self.tileSize, height: Self.tileSize))

        let barWidth = Self.tileSize * 0.9
        self.healthBarBackground = SKSpriteNode(
            color: UIColor.black.withAlphaComponent(0.25),
            size: CGSize(width: barWidth, height: 6)
        )
        self.healthBar = SKSpriteNode(
            color: .green,
            size: CGSize(width: barWidth, height: 6)
        )

        self.label = SKLabelNode(fontNamed: "Helvetica-Bold")
        label.fontSize = 11
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .top

        super.init()
        userData = ["plotID": plot.id.uuidString]
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Double-tap to open plot details"
        addChild(sprite)
        healthBarBackground.position = CGPoint(x: 0, y: Self.tileSize / 2 + 8)
        healthBar.position = healthBarBackground.position
        healthBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        healthBar.position.x = healthBarBackground.position.x - barWidth / 2
        addChild(healthBarBackground)
        addChild(healthBar)
        label.position = CGPoint(x: 0, y: -Self.tileSize / 2 - 4)
        addChild(label)

        applyVisuals(plot: plot)
        // Initial render — no animations, just baseline visuals + idle.
        updateIdleAnimation(for: plot.state)
    }

    private func updateAccessibilityLabel(plot: DBModel.FarmPlot) {
        let goalTitle = plot.goal?.title ?? "Common Field"
        let stateText: String
        switch plot.state {
        case .empty:     stateText = "empty"
        case .growing:   stateText = "growing"
        case .mature:    stateText = "mature"
        case .withered:  stateText = "withered"
        case .dead:      stateText = "dead"
        }
        accessibilityLabel = "\(goalTitle), \(stateText), \(plot.health)% health"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Re-render this node against a (possibly updated) plot row. Cheaper than
    /// destroying and recreating the node when a single field changes.
    /// Triggers transition animations when health/state change vs. last apply.
    func apply(plot: DBModel.FarmPlot) {
        let healthDelta = plot.health - lastHealth
        let stateChanged = plot.state != lastState
        let previousState = lastState

        plotID = plot.id
        userData = ["plotID": plot.id.uuidString]
        applyVisuals(plot: plot)

        // --- Transition animations -------------------------------------------
        if stateChanged {
            handleStateTransition(from: previousState, to: plot.state)
        }
        if healthDelta > 0, plot.state != .dead {
            playContributionPulse()
        }
        updateIdleAnimation(for: plot.state)

        lastHealth = plot.health
        lastState = plot.state
    }

    /// Static visual properties (texture, bar fill, label) — no actions. Split
    /// out so the animation paths above can re-use it without re-running
    /// transition detection.
    private func applyVisuals(plot: DBModel.FarmPlot) {
        sprite.texture = PlotTextureFactory.texture(
            for: plot.kind,
            state: plot.state,
            size: Self.tileSize
        )
        let clamped = max(0, min(100, plot.health))
        let fraction = CGFloat(clamped) / 100.0
        let barWidth = Self.tileSize * 0.9
        healthBar.size = CGSize(width: max(1, barWidth * fraction), height: 6)
        healthBar.color = barColor(for: clamped, state: plot.state)
        label.text = plot.goal?.title ?? "Common Field"
        updateAccessibilityLabel(plot: plot)
    }

    // MARK: - Animations

    /// Healthy plots breathe; withered/dead plots sit still. Idempotent — only
    /// (re)adds the action when its presence needs to change.
    private func updateIdleAnimation(for state: PlotState) {
        let shouldIdle = (state == .growing || state == .mature) && !UIAccessibility.isReduceMotionEnabled
        let hasIdle = sprite.action(forKey: ActionKey.idle) != nil
        if shouldIdle && !hasIdle {
            // Gentle ±0.04 rad sway, ~2s per cycle. Run on sprite only so the
            // health bar above doesn't tilt.
            let lean = SKAction.rotate(byAngle: 0.04, duration: 1.0)
            lean.timingMode = .easeInEaseOut
            let unlean = SKAction.rotate(byAngle: -0.08, duration: 2.0)
            unlean.timingMode = .easeInEaseOut
            let recenter = SKAction.rotate(byAngle: 0.04, duration: 1.0)
            recenter.timingMode = .easeInEaseOut
            sprite.run(
                SKAction.repeatForever(SKAction.sequence([lean, unlean, recenter])),
                withKey: ActionKey.idle
            )
        } else if !shouldIdle && hasIdle {
            sprite.removeAction(forKey: ActionKey.idle)
            sprite.run(SKAction.rotate(toAngle: 0, duration: 0.15))
        }
    }

    /// Brief scale pulse + radial sparkle burst when health goes up.
    private func playContributionPulse() {
        Task { @MainActor in SoundPlayer.shared.play(.contribution) }
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let scaleUp = SKAction.scale(to: 1.12, duration: 0.10)
        scaleUp.timingMode = .easeOut
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.15)
        scaleDown.timingMode = .easeIn
        sprite.run(SKAction.sequence([scaleUp, scaleDown]), withKey: ActionKey.pulse)

        let count = 6
        let radius: CGFloat = Self.tileSize * 0.55
        for index in 0..<count {
            let angle = (CGFloat(index) / CGFloat(count)) * 2 * .pi
            let sparkle = SKShapeNode(circleOfRadius: 3)
            sparkle.fillColor = UIColor(red: 1.0, green: 0.92, blue: 0.45, alpha: 1)
            sparkle.strokeColor = .clear
            sparkle.position = .zero
            sparkle.zPosition = 10
            addChild(sparkle)
            let target = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            let move = SKAction.move(to: target, duration: 0.45)
            move.timingMode = .easeOut
            let fade = SKAction.fadeOut(withDuration: 0.45)
            sparkle.run(SKAction.sequence([
                SKAction.group([move, fade]),
                SKAction.removeFromParent()
            ]))
        }
    }

    /// Quick rotational shake when a plot withers.
    private func playWitherShake() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let amplitude: CGFloat = 0.18
        let s1 = SKAction.rotate(toAngle:  amplitude, duration: 0.06)
        let s2 = SKAction.rotate(toAngle: -amplitude, duration: 0.10)
        let s3 = SKAction.rotate(toAngle:  amplitude * 0.5, duration: 0.08)
        let s4 = SKAction.rotate(toAngle: 0, duration: 0.06)
        sprite.run(SKAction.sequence([s1, s2, s3, s4]), withKey: ActionKey.shake)
    }

    /// Fade + slight shrink when a plot dies — leaves the sprite visible but
    /// muted so the user can still tap to re-plant.
    private func playDeathDissolve() {
        if UIAccessibility.isReduceMotionEnabled {
            sprite.alpha = 0.55
            sprite.setScale(0.85)
            return
        }
        let fade = SKAction.fadeAlpha(to: 0.55, duration: 0.45)
        fade.timingMode = .easeIn
        let shrink = SKAction.scale(to: 0.85, duration: 0.45)
        shrink.timingMode = .easeIn
        sprite.run(SKAction.group([fade, shrink]), withKey: ActionKey.dissolve)
    }

    /// Inverse of dissolve: restore alpha + scale when a dead plot is replanted.
    private func playRevive() {
        sprite.removeAction(forKey: ActionKey.dissolve)
        let fade = SKAction.fadeAlpha(to: 1.0, duration: 0.25)
        let grow = SKAction.scale(to: 1.0, duration: 0.25)
        sprite.run(SKAction.group([fade, grow]))
    }

    private func handleStateTransition(from old: PlotState, to new: PlotState) {
        switch (old, new) {
        case (_, .withered):
            playWitherShake()
        case (_, .dead):
            playDeathDissolve()
        case (.dead, .growing), (.dead, .mature):
            playRevive()
        default:
            // Reset transform so an alpha/scale change from a previous dead
            // state doesn't persist after revive via apply() rather than the
            // explicit replant path.
            if sprite.alpha < 1.0 || sprite.xScale < 1.0 {
                playRevive()
            }
        }
    }

    // MARK: - Helpers

    private func barColor(for health: Int, state: PlotState) -> UIColor {
        if state == .dead { return UIColor.darkGray }
        switch health {
        case 70...:    return UIColor(red: 0.20, green: 0.75, blue: 0.30, alpha: 1)
        case 35..<70:  return UIColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1)
        default:       return UIColor(red: 0.85, green: 0.30, blue: 0.25, alpha: 1)
        }
    }
}

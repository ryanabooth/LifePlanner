import SpriteKit

/// Visual representation of a single `FarmPlot` in the scene. Composed of:
/// - a base sprite clipped to a diamond via SKCropNode
/// - a thin health bar above the sprite (green → red as health drops)
/// - a label below showing the goal title (or "Common Field")
///
/// Tile size is not fixed — call `resize(to:)` from the scene's layout pass
/// so the grid can pack plots optimally into whatever screen space is available.
final class PlotNode: SKNode {

    /// The id of the corresponding `FarmPlot` row.
    private(set) var plotID: UUID

    private let sprite: SKSpriteNode
    private let healthBar: SKSpriteNode
    private let healthBarBackground: SKSpriteNode
    private let label: SKLabelNode

    /// Sprite renders at tileSize × spriteScale so the art overflows the grid
    /// cell and fills more of the screen. Bar/label anchor to spriteHalf.
    private static let spriteScale: CGFloat = 1.5

    /// Current rendered tile size; updated by `resize(to:)`.
    private var currentTileSize: CGFloat
    /// Tracked so `resize(to:)` can regenerate the texture without a full `apply`.
    private var currentKind: FarmElementType
    private var lastHealth: Int
    private var lastState: PlotState

    // MARK: - SKAction keys (so we can re-trigger without stacking)
    private enum ActionKey {
        static let idle     = "idle-sway"
        static let pulse    = "contrib-pulse"
        static let shake    = "wither-shake"
        static let dissolve = "death-dissolve"
    }

    var onAccessibilityActivate: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?()
        return true
    }

    init(plot: DBModel.FarmPlot) {
        let initialSize: CGFloat = 80

        self.plotID         = plot.id
        self.currentTileSize = initialSize
        self.currentKind    = plot.kind
        self.lastHealth     = plot.health
        self.lastState      = plot.state

        let spriteSize = initialSize * Self.spriteScale
        let texture = PlotTextureFactory.texture(for: plot.kind, state: plot.state, size: spriteSize)
        self.sprite = SKSpriteNode(texture: texture, size: CGSize(width: spriteSize * 0.8, height: spriteSize))

        let barWidth = initialSize * 0.9
        self.healthBarBackground = SKSpriteNode(
            color: UIColor.black.withAlphaComponent(0.25),
            size: CGSize(width: barWidth, height: 6)
        )
        self.healthBar = SKSpriteNode(color: .green, size: CGSize(width: barWidth, height: 6))

        self.label = SKLabelNode(fontNamed: "Helvetica-Bold")
        label.fontSize = 11
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode   = .top

        super.init()
        userData = ["plotID": plot.id.uuidString]
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint   = "Double-tap to open plot details"

        addChild(sprite)

        let spriteHalf = spriteSize / 2
        healthBarBackground.position = CGPoint(x: 0, y: -spriteHalf * 0.55 - 8)
        healthBar.position   = healthBarBackground.position
        healthBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        healthBar.position.x  = -barWidth / 2
        label.position = CGPoint(x: 0, y: -spriteHalf * 0.55 - 18)
        addChild(healthBarBackground)
        addChild(healthBar)
        addChild(label)

        applyVisuals(plot: plot)
        updateIdleAnimation(for: plot.state)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Resize

    /// Reshape all child nodes to a new tile size. Called by the scene layout
    /// pass so the grid can pack plots into the available screen area.
    func resize(to newTileSize: CGFloat) {
        guard abs(newTileSize - currentTileSize) > 0.5 else { return }
        currentTileSize = newTileSize

        let spriteSize = newTileSize * Self.spriteScale
        let spriteHalf = spriteSize / 2
        let barWidth   = newTileSize * 0.9

        sprite.size    = CGSize(width: spriteSize * 0.8, height: spriteSize)
        sprite.texture = PlotTextureFactory.texture(for: currentKind, state: lastState, size: spriteSize)

        healthBarBackground.size.width = barWidth
        healthBarBackground.position   = CGPoint(x: 0, y: -spriteHalf * 0.55 - 8)

        let fraction = CGFloat(max(0, min(100, lastHealth))) / 100
        healthBar.size.width = max(1, barWidth * fraction)
        healthBar.position   = CGPoint(x: -barWidth / 2, y: -spriteHalf * 0.55 - 8)

        label.position = CGPoint(x: 0, y: -spriteHalf * 0.55 - 18)
    }

    // MARK: - Apply

    func apply(plot: DBModel.FarmPlot) {
        let healthDelta  = plot.health - lastHealth
        let stateChanged = plot.state != lastState
        let previousState = lastState

        plotID   = plot.id
        userData = ["plotID": plot.id.uuidString]
        applyVisuals(plot: plot)

        if stateChanged { handleStateTransition(from: previousState, to: plot.state) }
        if healthDelta > 0, plot.state != .dead { playContributionPulse() }
        updateIdleAnimation(for: plot.state)

        lastHealth = plot.health
        lastState  = plot.state
    }

    private func applyVisuals(plot: DBModel.FarmPlot) {
        currentKind    = plot.kind
        sprite.texture = PlotTextureFactory.texture(for: plot.kind, state: plot.state, size: currentTileSize)
        let clamped    = max(0, min(100, plot.health))
        let fraction   = CGFloat(clamped) / 100.0
        let barWidth   = currentTileSize * 0.9
        healthBar.size = CGSize(width: max(1, barWidth * fraction), height: 6)
        healthBar.color = barColor(for: clamped, state: plot.state)
        label.text = plot.goal?.title ?? "Common Field"
        updateAccessibilityLabel(plot: plot)
    }

    private func updateAccessibilityLabel(plot: DBModel.FarmPlot) {
        let goalTitle = plot.goal?.title ?? "Common Field"
        let stateText: String
        switch plot.state {
        case .empty:    stateText = "empty"
        case .growing:  stateText = "growing"
        case .mature:   stateText = "mature"
        case .withered: stateText = "withered"
        case .dead:     stateText = "dead"
        }
        accessibilityLabel = "\(goalTitle), \(stateText), \(plot.health)% health"
    }

    // MARK: - Animations

    private func updateIdleAnimation(for state: PlotState) {
        let shouldIdle = (state == .growing || state == .mature) && !UIAccessibility.isReduceMotionEnabled
        let hasIdle    = sprite.action(forKey: ActionKey.idle) != nil
        if shouldIdle && !hasIdle {
            let lean     = SKAction.rotate(byAngle:  0.04, duration: 1.0)
            let unlean   = SKAction.rotate(byAngle: -0.08, duration: 2.0)
            let recenter = SKAction.rotate(byAngle:  0.04, duration: 1.0)
            lean.timingMode = .easeInEaseOut
            unlean.timingMode = .easeInEaseOut
            recenter.timingMode = .easeInEaseOut
            sprite.run(.repeatForever(.sequence([lean, unlean, recenter])), withKey: ActionKey.idle)
        } else if !shouldIdle && hasIdle {
            sprite.removeAction(forKey: ActionKey.idle)
            sprite.run(.rotate(toAngle: 0, duration: 0.15))
        }
    }

    private func playContributionPulse() {
        Task { @MainActor in SoundPlayer.shared.play(.contribution) }
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let up   = SKAction.scale(to: 1.12, duration: 0.10)
        let down = SKAction.scale(to: 1.00, duration: 0.15)
        up.timingMode = .easeOut; down.timingMode = .easeIn
        sprite.run(.sequence([up, down]), withKey: ActionKey.pulse)

        let count  = 6
        let radius = currentTileSize * Self.spriteScale * 0.55
        for i in 0..<count {
            let angle   = CGFloat(i) / CGFloat(count) * 2 * .pi
            let sparkle = SKShapeNode(circleOfRadius: 3)
            sparkle.fillColor   = UIColor(red: 1.0, green: 0.92, blue: 0.45, alpha: 1)
            sparkle.strokeColor = .clear
            sparkle.position    = .zero
            sparkle.zPosition   = 10
            addChild(sparkle)
            let move = SKAction.move(to: CGPoint(x: cos(angle) * radius, y: sin(angle) * radius), duration: 0.45)
            move.timingMode = .easeOut
            sparkle.run(.sequence([.group([move, .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
        }
    }

    private func playWitherShake() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        sprite.run(.sequence([
            .rotate(toAngle:  0.18, duration: 0.06),
            .rotate(toAngle: -0.18, duration: 0.10),
            .rotate(toAngle:  0.09, duration: 0.08),
            .rotate(toAngle:  0.00, duration: 0.06)
        ]), withKey: ActionKey.shake)
    }

    private func playDeathDissolve() {
        if UIAccessibility.isReduceMotionEnabled { sprite.alpha = 0.55; sprite.setScale(0.85); return }
        let fade   = SKAction.fadeAlpha(to: 0.55, duration: 0.45)
        let shrink = SKAction.scale(to: 0.85, duration: 0.45)
        fade.timingMode = .easeIn; shrink.timingMode = .easeIn
        sprite.run(.group([fade, shrink]), withKey: ActionKey.dissolve)
    }

    private func playRevive() {
        sprite.removeAction(forKey: ActionKey.dissolve)
        sprite.run(.group([.fadeAlpha(to: 1.0, duration: 0.25), .scale(to: 1.0, duration: 0.25)]))
    }

    private func handleStateTransition(from old: PlotState, to new: PlotState) {
        switch (old, new) {
        case (_, .withered): playWitherShake()
        case (_, .dead):     playDeathDissolve()
        case (.dead, .growing), (.dead, .mature): playRevive()
        default:
            if sprite.alpha < 1.0 || sprite.xScale < 1.0 { playRevive() }
        }
    }

    private func barColor(for health: Int, state: PlotState) -> UIColor {
        if state == .dead { return .darkGray }
        switch health {
        case 70...:   return UIColor(red: 0.20, green: 0.75, blue: 0.30, alpha: 1)
        case 35..<70: return UIColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1)
        default:      return UIColor(red: 0.85, green: 0.30, blue: 0.25, alpha: 1)
        }
    }

}

import SpriteKit

/// Visual representation of a single `FarmPlot` in the scene. Composed of:
/// - a base sprite (texture provided by `PlotTextureFactory`)
/// - a thin health bar above the sprite (green → red as health drops)
/// - a label below showing the goal title (or "Common Field")
///
/// The associated `FarmPlot.id` is stashed on `userData` so Step 6's tap
/// handling can resolve back to the model row.
final class PlotNode: SKNode {

    /// Size of the underlying tile in points.
    static let tileSize: CGFloat = 80

    /// The id of the corresponding `FarmPlot` row. Empty UUID for nodes built
    /// from a literal (none currently).
    private(set) var plotID: UUID

    private let sprite: SKSpriteNode
    private let healthBar: SKSpriteNode
    private let healthBarBackground: SKSpriteNode
    private let label: SKLabelNode

    init(plot: DBModel.FarmPlot) {
        self.plotID = plot.id
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
        addChild(sprite)
        healthBarBackground.position = CGPoint(x: 0, y: Self.tileSize / 2 + 8)
        healthBar.position = healthBarBackground.position
        healthBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        healthBar.position.x = healthBarBackground.position.x - barWidth / 2
        addChild(healthBarBackground)
        addChild(healthBar)
        label.position = CGPoint(x: 0, y: -Self.tileSize / 2 - 4)
        addChild(label)

        apply(plot: plot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Re-render this node against a (possibly updated) plot row. Cheaper than
    /// destroying and recreating the node when a single field changes.
    func apply(plot: DBModel.FarmPlot) {
        plotID = plot.id
        userData = ["plotID": plot.id.uuidString]
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
    }

    private func barColor(for health: Int, state: PlotState) -> UIColor {
        if state == .dead { return UIColor.darkGray }
        switch health {
        case 70...:    return UIColor(red: 0.20, green: 0.75, blue: 0.30, alpha: 1)
        case 35..<70:  return UIColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1)
        default:       return UIColor(red: 0.85, green: 0.30, blue: 0.25, alpha: 1)
        }
    }
}

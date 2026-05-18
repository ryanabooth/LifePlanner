import SpriteKit
import Combine

/// SpriteKit scene rendering the farm. Stateless — every visible change comes
/// from `snapshot(plots:gold:capacity:)`, called by the SwiftUI host whenever
/// `@Query` results change. The scene itself just lays things out and emits
/// tap events.
///
/// Tap events are published via `tappedPlotID` so Step 6's SwiftUI overlays
/// can subscribe without coupling to SpriteKit.
final class FarmScene: SKScene {

    /// Published when the user taps a plot. Step 6 uses this to present
    /// `PlotDetailSheet`. Empty in v1 (tap is a no-op until the sheet exists).
    let tappedPlotID = PassthroughSubject<UUID, Never>()

    /// Published when the user taps the farmhouse — triggers the dev menu.
    let tappedFarmhouse = PassthroughSubject<Void, Never>()

    // HUD nodes are eager stored properties because `didChangeSize` fires during
    // `init(size:)` — before `didMove(to:)` — and the layout helpers read them.
    // Building them in `setupHUD()` post-init would force-unwrap nils.
    private let titleLabel: SKLabelNode = {
        let label = SKLabelNode(fontNamed: "Helvetica-Bold")
        label.text = "Your Farm"
        label.fontSize = 20
        label.fontColor = .white
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        return label
    }()
    private let goldLabel: SKLabelNode = {
        let label = SKLabelNode(fontNamed: "Helvetica-Bold")
        label.text = "🪙 0"
        label.fontSize = 20
        label.fontColor = .white
        label.horizontalAlignmentMode = .right
        label.verticalAlignmentMode = .top
        return label
    }()
    private let capacityLabel: SKLabelNode = {
        let label = SKLabelNode(fontNamed: "Helvetica")
        label.text = "Capacity: 0 / 3"
        label.fontSize = 13
        label.fontColor = UIColor.white.withAlphaComponent(0.9)
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        return label
    }()

    private let plotsContainer = SKNode()
    private var plotNodes: [UUID: PlotNode] = [:]

    /// Tracks the last-seen gold so `snapshot` can detect increases and fire
    /// the celebration. Starts at -1 so the very first snapshot doesn't pulse.
    private var lastKnownGold: Int = -1

    /// Decorative butterflies + birds that wander the scene background.
    /// Populated once in `didMove`; runs forever via its own SKActions.
    private let ambientLife = AmbientLifeController()

    /// Phase 3 cosmetic scene objects. Populated on `didMove`; updated via
    /// `snapshotCosmetics(...)` whenever owned/equipped cosmetics change.
    private let avatarController = AvatarController()
    private let petController = PetController()
    private let farmhouseDecoration = FarmhouseNode()

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        backgroundColor = SKColor(red: 0.62, green: 0.82, blue: 0.45, alpha: 1.0)
        scaleMode = .resizeFill
        // didMove fires after init; nodes might already have parents if the
        // scene is reused. Guard with parent checks so we don't double-add.
        if titleLabel.parent == nil { addChild(titleLabel) }
        if goldLabel.parent == nil { addChild(goldLabel) }
        if capacityLabel.parent == nil { addChild(capacityLabel) }
        if plotsContainer.parent == nil { addChild(plotsContainer) }
        if farmhouseDecoration.parent == nil {
            farmhouseDecoration.zPosition = -0.5
            addChild(farmhouseDecoration)
        }
        ambientLife.populate(in: self)
        avatarController.populate(in: self)
        petController.populate(in: self)
        layoutHUD()
        layoutFarmhouse()
        // Looping farm ambience. Silent until sfx_farm_ambience.{caf,mp3,wav,m4a}
        // is added to the bundle.
        SoundPlayer.shared.startAmbience()
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        SoundPlayer.shared.stopAmbience()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutHUD()
        layoutPlots()
        layoutFarmhouse()
    }

    // MARK: - Snapshot

    /// The single entrypoint for re-rendering. Idempotent / diff-friendly:
    /// reuses existing `PlotNode`s when their `plotID` is still present, only
    /// creating / destroying nodes when the plot set changes.
    func snapshot(plots: [DBModel.FarmPlot], gold: Int, capacity: Int) {
        let goldIncreased = lastKnownGold >= 0 && gold > lastKnownGold
        lastKnownGold = gold
        goldLabel.text = "🪙 \(gold)"
        if goldIncreased {
            pulseGoldLabel()
            burstConfetti(at: goldLabel.position)
        }
        capacityLabel.text = "Capacity: \(plots.filter { $0.kind != .commonField }.count) / \(capacity)"

        let sorted = plots.sorted { $0.gridX < $1.gridX }
        let incomingIDs = Set(sorted.map(\.id))

        // Remove nodes whose plots no longer exist.
        for (id, node) in plotNodes where !incomingIDs.contains(id) {
            node.removeFromParent()
            plotNodes.removeValue(forKey: id)
        }

        // Upsert nodes for every plot still in the result set.
        for plot in sorted {
            if let existing = plotNodes[plot.id] {
                existing.apply(plot: plot)
            } else {
                let node = PlotNode(plot: plot)
                node.onAccessibilityActivate = { [weak self, id = plot.id] in
                    self?.tappedPlotID.send(id)
                }
                plotNodes[plot.id] = node
                plotsContainer.addChild(node)
            }
        }

        layoutPlots(orderedPlots: sorted)
    }

    // MARK: - Touch handling

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let hitNodes = nodes(at: location)

        let farmhouseTapped = hitNodes.contains { node in
            var current: SKNode? = node
            while let n = current {
                if n === farmhouseDecoration { return true }
                current = n.parent
            }
            return false
        }
        if farmhouseTapped {
            tappedFarmhouse.send()
            return
        }

        let hit = hitNodes.first { $0.userData?["plotID"] != nil }
        guard
            let idString = hit?.userData?["plotID"] as? String,
            let id = UUID(uuidString: idString)
        else { return }
        tappedPlotID.send(id)
    }

    // MARK: - Celebration

    private func pulseGoldLabel() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        goldLabel.removeAction(forKey: "goldPulse")
        let duration: TimeInterval = 0.55
        let pulse = SKAction.customAction(withDuration: duration) { node, elapsed in
            guard let label = node as? SKLabelNode else { return }
            let t = elapsed / CGFloat(duration)
            // 0→0.3: ramp to peak; 0.3→1.0: ease back
            let phase: CGFloat = t < 0.3 ? t / 0.3 : 1.0 - (t - 0.3) / 0.7
            label.fontColor = UIColor(red: 1.0, green: 1.0, blue: 1.0 - phase * 0.85, alpha: 1.0)
            label.setScale(1.0 + phase * 0.35)
        }
        let restore = SKAction.run { [weak goldLabel] in
            goldLabel?.fontColor = .white
            goldLabel?.setScale(1.0)
        }
        goldLabel.run(.sequence([pulse, restore]), withKey: "goldPulse")
    }

    private func burstConfetti(at origin: CGPoint) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let colors: [UIColor] = [.systemYellow, .systemOrange, .systemGreen, .white, .systemCyan, .systemPink]
        let count = 18
        for i in 0..<count {
            let particle = SKShapeNode(rectOf: CGSize(width: 6, height: 6), cornerRadius: 1)
            particle.fillColor = colors[i % colors.count]
            particle.strokeColor = .clear
            particle.position = origin
            particle.zPosition = 20
            particle.zRotation = CGFloat.random(in: 0 ..< .pi * 2)
            addChild(particle)

            let angle = CGFloat(i) / CGFloat(count) * .pi * 2 + CGFloat.random(in: -0.2...0.2)
            let distance = CGFloat.random(in: 55...110)
            let move = SKAction.moveBy(
                x: cos(angle) * distance,
                y: sin(angle) * distance,
                duration: 0.65
            )
            move.timingMode = .easeOut
            let spin = SKAction.rotate(byAngle: CGFloat.random(in: -.pi * 2 ... .pi * 2), duration: 0.65)
            let fade = SKAction.sequence([
                .fadeIn(withDuration: 0.05),
                .wait(forDuration: 0.2),
                .fadeOut(withDuration: 0.4)
            ])
            particle.run(.sequence([.group([move, spin, fade]), .removeFromParent()]))
        }
    }

    // MARK: - Layout

    /// Vertical inset reserved at the top of the scene for the status bar /
    /// notch. SwiftUI doesn't bleed safe-area into a SpriteView so we pass it
    /// in explicitly from `FarmTabView`.
    var topSafeAreaInset: CGFloat = 60 {
        didSet { layoutHUD() }
    }

    /// Height of the tab bar + home indicator at the bottom. Used to keep the
    /// plot grid above the tab bar. Passed in from `FarmTabView`.
    var bottomSafeAreaInset: CGFloat = 83 {
        didSet { layoutPlots() }
    }

    private func layoutHUD() {
        // Skip if the scene hasn't been sized yet (zero-size during init).
        guard size.width > 0, size.height > 0 else { return }
        let hudTop = size.height - topSafeAreaInset
        titleLabel.position = CGPoint(x: 20, y: hudTop)
        goldLabel.position = CGPoint(x: size.width - 20, y: hudTop)
        capacityLabel.position = CGPoint(x: 20, y: hudTop - 26)
    }

    // MARK: - Cosmetics

    /// Push equipped cosmetic slugs into the scene. Called by `FarmTabView`
    /// whenever `@Query` results for `OwnedCosmetic` change.
    func snapshotCosmetics(
        equippedHatSlug: String?,
        equippedOutfitSlug: String?,
        equippedPetSlug: String?,
        equippedDecorSlug: String?
    ) {
        avatarController.applyCosmetics(hatSlug: equippedHatSlug, outfitSlug: equippedOutfitSlug)
        petController.applyCosmetics(petSlug: equippedPetSlug)
        farmhouseDecoration.applyDecor(slug: equippedDecorSlug)
    }

    // MARK: - Season

    /// Apply season-specific background tint and ambient particle effects.
    /// Called by `FarmTabView` on appear and whenever the season changes.
    /// Safe to call multiple times — effects are replaced, not accumulated.
    func applySeason(_ season: Season, reduceMotion: Bool) {
        backgroundColor = season.backgroundColor
        ambientLife.applySeasonalEffects(season, reduceMotion: reduceMotion)
    }

    private func layoutFarmhouse() {
        guard size.width > 0, size.height > 0 else { return }
        farmhouseDecoration.position = CGPoint(
            x: size.width * 0.20,
            y: size.height * 0.62
        )
    }

    private func layoutPlots(orderedPlots: [DBModel.FarmPlot]? = nil) {
        let ordered: [PlotNode]
        if let orderedPlots {
            ordered = orderedPlots.compactMap { plotNodes[$0.id] }
        } else {
            ordered = plotNodes.values.sorted { $0.position.x < $1.position.x }
        }
        guard !ordered.isEmpty, size.width > 0, size.height > 0 else { return }

        let count = ordered.count
        let hPad: CGFloat      = 10
        let colSpacing: CGFloat = 10
        let rowSpacing: CGFloat = 28
        let maxTile: CGFloat   = 120

        let availableW = size.width - hPad * 2
        // Vertical band: from just below the farmhouse area down to above the tab bar.
        let gridTop    = size.height * 0.60
        let gridBottom = bottomSafeAreaInset + 20
        let availableH = max(80, gridTop - gridBottom)

        // Find the column count that maximises tile size within the available rect.
        var bestTile: CGFloat = 0
        var bestCols = 1
        for cols in 1...count {
            let rows  = Int(ceil(Double(count) / Double(cols)))
            let tileW = (availableW - CGFloat(cols - 1) * colSpacing) / CGFloat(cols)
            let tileH = (availableH - CGFloat(rows - 1) * rowSpacing) / CGFloat(rows)
            let tile  = min(tileW, tileH, maxTile)
            if tile > bestTile { bestTile = tile; bestCols = cols }
        }

        let cols = bestCols
        let rows = Int(ceil(Double(count) / Double(cols)))
        let tile = max(40, bestTile)

        for node in ordered { node.resize(to: tile) }

        let totalW   = CGFloat(cols) * tile + CGFloat(cols - 1) * colSpacing
        let totalH   = CGFloat(rows) * tile + CGFloat(rows - 1) * rowSpacing
        let originX  = (size.width - totalW) / 2 + tile / 2
        let bandMidY = gridBottom + availableH / 2
        let originY  = bandMidY + (totalH - tile) / 2

        for (index, node) in ordered.enumerated() {
            let col    = index % cols
            let row    = index / cols
            let target = CGPoint(
                x: originX + CGFloat(col) * (tile + colSpacing),
                y: originY - CGFloat(row) * (tile + rowSpacing)
            )
            node.removeAction(forKey: "layout")
            if UIAccessibility.isReduceMotionEnabled {
                node.position = target
            } else {
                node.run(SKAction.move(to: target, duration: 0.15), withKey: "layout")
            }
        }
    }
}

import SwiftUI
import SwiftData
import SpriteKit
import Combine

/// SwiftUI host for the SpriteKit farm scene. Watches `FarmPlot` and
/// `FarmState` with `@Query`; pushes snapshots into the scene whenever the
/// reactive results change.
///
/// Step 5: read-only render — no overlays yet.
/// Step 6: subscribes to `scene.tappedPlotID` to present `PlotDetailSheet`,
/// and adds a quest-log button to the HUD.
struct FarmTabView: View {

    @Query private var plots: [DBModel.FarmPlot]
    @Query private var farmStates: [DBModel.FarmState]

    /// Persisted across re-renders so SpriteView doesn't reset every body
    /// evaluation. Size is provisional — the scene uses `.resizeFill` so it
    /// adopts the real view bounds once `SpriteView` lays it out.
    @State private var scene: FarmScene = {
        let s = FarmScene(size: CGSize(width: 400, height: 800))
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        GeometryReader { proxy in
            SpriteView(scene: scene)
                .ignoresSafeArea()
                .onAppear {
                    scene.topSafeAreaInset = proxy.safeAreaInsets.top + 12
                    pushSnapshot()
                }
                .onChange(of: snapshotSignature) { _, _ in pushSnapshot() }
                .onChange(of: proxy.safeAreaInsets.top) { _, newInset in
                    scene.topSafeAreaInset = newInset + 12
                }
        }
    }

    /// Signature that changes whenever any rendered property changes — plot
    /// identity, health, state, kind, or the gold balance. SwiftUI's onChange
    /// only fires when the integer differs, so this is cheaper than diffing
    /// every plot row by hand.
    private var snapshotSignature: Int {
        var hasher = Hasher()
        hasher.combine(plots.count)
        for plot in plots {
            hasher.combine(plot.id)
            hasher.combine(plot.health)
            hasher.combine(plot.state.rawValue)
            hasher.combine(plot.kind.rawValue)
            hasher.combine(plot.gridX)
        }
        hasher.combine(farmStates.first?.gold ?? 0)
        hasher.combine(farmStates.first?.plotCapacity ?? 0)
        return hasher.finalize()
    }

    private func pushSnapshot() {
        scene.snapshot(
            plots: plots,
            gold: farmStates.first?.gold ?? 0,
            capacity: farmStates.first?.plotCapacity ?? 0
        )
    }
}

#Preview {
    FarmTabView()
        .modelContainer(for: [
            DBModel.FarmState.self, DBModel.FarmPlot.self, DBModel.Goal.self,
            DBModel.Task.self, DBModel.Habit.self, DBModel.HabitLogEntry.self,
            DBModel.Quest.self
        ], inMemory: true)
}

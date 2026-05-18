import SwiftUI
import SwiftData

/// Spend gold to grow `FarmState.plotCapacity` by one — unlocking room for
/// another Goal-bound plot. Step 7 surfaces this from over-capacity goal
/// creation; for now it's reachable from the HUD button.
struct CapacityUpgradeSheet: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var farmStates: [DBModel.FarmState]
    @Query private var plots: [DBModel.FarmPlot]

    private var state: DBModel.FarmState? { farmStates.first }
    private var usedPlots: Int { plots.filter { $0.kind != .commonField }.count }
    private var upgradeCost: Int {
        FarmTuning.upgradeCost(currentCapacity: state?.plotCapacity ?? 3)
    }
    private var canAfford: Bool { (state?.gold ?? 0) >= upgradeCost }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Capacity") {
                        Text("\(usedPlots) / \(state?.plotCapacity ?? 0)")
                    }
                    LabeledContent("Gold") {
                        Text("🪙 \(state?.gold ?? 0)")
                    }
                }

                Section {
                    Button {
                        try? injected.interactors.farm.purchaseCapacity(in: modelContext)
                        SoundPlayer.shared.play(.purchase)
                        HapticPlayer.shared.success()
                    } label: {
                        Label(
                            "Buy 1 plot (–\(upgradeCost) gold)",
                            systemImage: "plus.square.dashed"
                        )
                    }
                    .disabled(!canAfford)
                } footer: {
                    Text("Each upgrade lets you bind one more Goal to its own farm plot. Cost grows with each upgrade.")
                }
            }
            .navigationTitle("Expand Farm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

import SwiftUI
import SwiftData

struct DevMenuView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DBModel.FarmPlot.gridX) private var plots: [DBModel.FarmPlot]
    @Query private var farmStates: [DBModel.FarmState]
    @Query private var ownedCosmetics: [DBModel.OwnedCosmetic]

    @State private var goldInput: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Plot Health") {
                    ForEach(plots) { plot in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(plotLabel(plot))
                                    .font(.headline)
                                Spacer()
                                Text("Health: \(plot.health)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                healthButton("Withered", plot: plot, health: 1, state: .withered)
                                healthButton("50", plot: plot, health: 50, state: .growing)
                                healthButton("Mature", plot: plot, health: FarmTuning.matureThreshold, state: .mature)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Gold") {
                    HStack {
                        Text("Current: \(farmStates.first?.gold ?? 0)")
                        Spacer()
                        TextField("Amount", text: $goldInput)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Button("Set") {
                            if let value = Int(goldInput), let state = farmStates.first {
                                state.gold = max(0, value)
                                modelContext.saveQuietly()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(Int(goldInput) == nil)
                    }
                }

                Section("Farmhouse Decor") {
                    HStack(spacing: 8) {
                        decorButton("Default", slug: nil)
                        decorButton("Red Roof", slug: "house_red_roof")
                        decorButton("Blue Roof", slug: "house_blue_roof")
                        decorButton("Flowers", slug: "house_flower_box")
                    }
                }
            }
            .navigationTitle("Dev Menu")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func healthButton(_ label: String, plot: DBModel.FarmPlot, health: Int, state: PlotState) -> some View {
        Button(label) {
            plot.health = health
            plot.state = state
            modelContext.saveQuietly()
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }

    private func plotLabel(_ plot: DBModel.FarmPlot) -> String {
        if let title = plot.goal?.title { return title }
        return plot.kind.label
    }

    /// Grants (if needed, bypassing gold cost like the other dev shortcuts
    /// above) and equips the given farmhouse decor slug, or un-equips
    /// whatever's currently equipped when `slug` is `nil` (default look).
    private func decorButton(_ label: String, slug: String?) -> some View {
        Button(label) {
            guard let slug else {
                if let equipped = injected.interactors.cosmetics.equipped(kind: .farmhouseDecor, in: modelContext) {
                    injected.interactors.cosmetics.unequip(equipped, in: modelContext)
                }
                return
            }
            let cosmetic = ownedCosmetics.first { $0.slug == slug }
                ?? {
                    let new = DBModel.OwnedCosmetic(slug: slug, kind: .farmhouseDecor)
                    modelContext.insert(new)
                    return new
                }()
            injected.interactors.cosmetics.equip(cosmetic, in: modelContext)
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }
}

#Preview {
    DevMenuView()
        .modelContainer(for: [
            DBModel.FarmPlot.self, DBModel.FarmState.self, DBModel.Goal.self
        ], inMemory: true)
}

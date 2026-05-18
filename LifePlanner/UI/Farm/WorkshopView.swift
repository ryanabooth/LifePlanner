import SwiftUI
import SwiftData

/// Sheet presenting all purchasable farm tools. Tools are always active once
/// bought — no equip/unequip flow. Bonuses stack additively.
struct WorkshopView: View {

    @Environment(\.injected) private var injected
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\DBModel.OwnedTool.purchasedAt)])
    private var ownedTools: [DBModel.OwnedTool]

    @Query private var farmStates: [DBModel.FarmState]

    @State private var errorMessage: String?
    @State private var showError = false

    private var gold: Int { farmStates.first?.gold ?? 0 }

    var body: some View {
        List {
            goldSection
            toolsSection
        }
        .navigationTitle("Workshop")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Purchase failed", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Sections

    private var goldSection: some View {
        Section {
            Label("🪙 \(gold) gold available", systemImage: "")
                .labelStyle(.titleOnly)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private var toolsSection: some View {
        Section {
            ForEach(ToolCatalog.all, id: \.slug) { tool in
                ToolRow(
                    tool: tool,
                    isOwned: ownedTools.contains { $0.slug == tool.slug },
                    canAfford: gold >= tool.goldCost
                ) {
                    buyTool(slug: tool.slug)
                }
            }
        } header: {
            Text("Available tools")
        } footer: {
            Text("Tool bonuses stack additively and apply immediately.")
        }
    }

    // MARK: - Actions

    private func buyTool(slug: String) {
        do {
            try injected.interactors.tools.purchase(slug: slug, in: modelContext)
        } catch EconomyError.insufficientGold(let have, let need) {
            errorMessage = "You need \(need) gold but only have \(have)."
            showError = true
        } catch ToolError.alreadyOwned {
            errorMessage = "You already own this tool."
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Tool Row

private struct ToolRow: View {

    let tool: ToolDefinition
    let isOwned: Bool
    let canAfford: Bool
    let onBuy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(tool.emoji)
                .font(.largeTitle)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(tool.name)
                        .font(.headline)
                    if isOwned {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    }
                }
                Text(tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                bonusLabel
            }

            Spacer()

            if !isOwned {
                Button {
                    onBuy()
                } label: {
                    Label("🪙 \(tool.goldCost)", systemImage: "")
                        .labelStyle(.titleOnly)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(canAfford ? Color.accentColor : Color.secondary.opacity(0.3),
                                    in: Capsule())
                        .foregroundStyle(canAfford ? .white : .secondary)
                }
                .disabled(!canAfford)
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(canAfford
                    ? "Buy \(tool.name) for \(tool.goldCost) gold"
                    : "Can't afford \(tool.name) — costs \(tool.goldCost) gold")
            }
        }
        .padding(.vertical, 4)
        .opacity(isOwned ? 0.7 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        var parts = [tool.name, tool.description]
        if tool.habitBonus > 0 { parts.append("plus \(tool.habitBonus) habit bonus") }
        else if tool.taskBonus > 0 { parts.append("plus \(tool.taskBonus) task bonus") }
        if isOwned {
            parts.append("owned")
        } else {
            parts.append(canAfford
                ? "costs \(tool.goldCost) gold"
                : "costs \(tool.goldCost) gold, not enough gold")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var bonusLabel: some View {
        if tool.habitBonus > 0 {
            Text("+\(tool.habitBonus) habit bonus")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.teal)
        } else if tool.taskBonus > 0 {
            Text("+\(tool.taskBonus) task bonus")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    WorkshopView()
        .modelContainer(for: [
            DBModel.FarmState.self, DBModel.OwnedTool.self
        ], inMemory: true)
        .inject(DIContainer(appState: AppState(), interactors: .stub))
}

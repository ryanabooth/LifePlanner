import SwiftUI
import SwiftData

struct CosmeticShopView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var ownedCosmetics: [DBModel.OwnedCosmetic]
    @Query private var farmStates: [DBModel.FarmState]

    @State private var selectedKind: CosmeticKind = .hat
    @State private var purchaseError: String?

    private var gold: Int { farmStates.first?.gold ?? 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("🪙 \(gold) gold")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(.systemGroupedBackground))

                Picker("Category", selection: $selectedKind) {
                    ForEach(CosmeticKind.allCases) { kind in
                        Text(kind.pickerLabel).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                List {
                    ForEach(CosmeticCatalog.all.filter { $0.kind == selectedKind }) { item in
                        CosmeticRow(
                            item: item,
                            owned: ownedCosmetics.first { $0.slug == item.slug },
                            gold: gold,
                            onPurchase: { purchase(item) },
                            onEquip: { toggle(item) }
                        )
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Cosmetic Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Can't purchase",
                isPresented: Binding(
                    get: { purchaseError != nil },
                    set: { if !$0 { purchaseError = nil } }
                )
            ) {
                Button("OK") { purchaseError = nil }
            } message: {
                Text(purchaseError ?? "")
            }
        }
    }

    private func purchase(_ item: CosmeticCatalogItem) {
        do {
            try injected.interactors.cosmetics.purchase(slug: item.slug, in: modelContext)
            SoundPlayer.shared.play(.purchase)
            HapticPlayer.shared.success()
        } catch EconomyError.insufficientGold(let have, let need) {
            purchaseError = "Not enough gold — you have \(have) but \(item.name) costs \(need)."
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func toggle(_ item: CosmeticCatalogItem) {
        guard let cosmetic = ownedCosmetics.first(where: { $0.slug == item.slug }) else { return }
        if cosmetic.equippedAt != nil {
            injected.interactors.cosmetics.unequip(cosmetic, in: modelContext)
        } else {
            injected.interactors.cosmetics.equip(cosmetic, in: modelContext)
        }
    }
}

// MARK: - Row

private struct CosmeticRow: View {
    let item: CosmeticCatalogItem
    let owned: DBModel.OwnedCosmetic?
    let gold: Int
    let onPurchase: () -> Void
    let onEquip: () -> Void

    private var isOwned: Bool { owned != nil }
    private var isEquipped: Bool { owned?.equippedAt != nil }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(width: 50, height: 50)
                .overlay { Text(item.kind.icon).font(.title2) }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.name)
                        .font(.body)
                        .fontWeight(.medium)
                    if isEquipped {
                        Text("Equipped")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.2), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isOwned {
                Button(isEquipped ? "Unequip" : "Equip", action: onEquip)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button("🪙 \(item.goldCost)", action: onPurchase)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(gold < item.goldCost)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityHint(isOwned ? (isEquipped ? "Double-tap to unequip" : "Double-tap to equip") : "Double-tap to purchase for \(item.goldCost) gold")
    }

    private var rowAccessibilityLabel: String {
        var parts = [item.name, item.description]
        if isEquipped    { parts.append("equipped") }
        else if isOwned  { parts.append("owned") }
        else             { parts.append("\(item.goldCost) gold") }
        if !isOwned && gold < item.goldCost { parts.append("not enough gold") }
        return parts.joined(separator: ", ")
    }
}

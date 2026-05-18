import SwiftUI
import SwiftData

/// Displays all achievements from `AchievementCatalog` in a scrollable grid.
/// Unlocked rows show the unlock date; locked rows are dimmed.
struct TrophyShelfView: View {

    @Query(sort: [SortDescriptor(\DBModel.Achievement.unlockedAt)])
    private var unlocked: [DBModel.Achievement]

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(AchievementCatalog.all, id: \.slug) { def in
                    AchievementTile(
                        definition: def,
                        unlockedAt: unlocked.first(where: { $0.slug == def.slug })?.unlockedAt
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Trophy Shelf")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tile

private struct AchievementTile: View {

    let definition: AchievementDefinition
    let unlockedAt: Date?

    private var isUnlocked: Bool { unlockedAt != nil }

    var body: some View {
        VStack(spacing: 8) {
            Text(definition.emoji)
                .font(.largeTitle)
                .saturation(isUnlocked ? 1.0 : 0.0)
                .opacity(isUnlocked ? 1.0 : 0.35)

            Text(definition.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(definition.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let date = unlockedAt {
                Text(date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Locked")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if let date = unlockedAt {
            let formatted = date.formatted(.dateTime.month(.abbreviated).day().year())
            return "\(definition.title). \(definition.description). Unlocked \(formatted)."
        }
        return "\(definition.title). \(definition.description). Locked."
    }
}

#Preview {
    NavigationStack {
        TrophyShelfView()
    }
    .modelContainer(for: [DBModel.Achievement.self], inMemory: true)
}

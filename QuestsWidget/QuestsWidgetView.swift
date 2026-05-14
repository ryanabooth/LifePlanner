import SwiftUI
import WidgetKit

struct QuestsWidgetView: View {

    var entry: QuestEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        default:
            mediumView
        }
    }

    // MARK: - Small (gold + quest count)

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("🪙 \(entry.gold)")
                    .font(.caption2.bold())
                Spacer()
                Text("Quests")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            let done = entry.quests.filter(\.isCompleted).count
            Text("\(done) / \(entry.quests.count)")
                .font(.title2.bold())
            Text("completed today")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Medium (quest list + weekly bar)

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Today's Quests")
                    .font(.caption.bold())
                Spacer()
                Text("🪙 \(entry.gold)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(entry.quests) { quest in
                HStack(spacing: 6) {
                    Image(systemName: quest.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(quest.isCompleted ? .green : .secondary)
                        .font(.caption)
                    Text(quest.title)
                        .font(.caption)
                        .lineLimit(1)
                        .strikethrough(quest.isCompleted)
                        .foregroundStyle(quest.isCompleted ? .secondary : .primary)
                    Spacer()
                    Text("🪙 \(quest.goldReward)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if entry.weeklyTarget > 0 {
                Divider()
                HStack(spacing: 6) {
                    Text("🌾 Week")
                        .font(.caption2)
                    ProgressView(
                        value: Double(entry.weeklyProgress),
                        total: Double(entry.weeklyTarget)
                    )
                    .tint(.green)
                    Text("\(entry.weeklyProgress)/\(entry.weeklyTarget)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct QuestsWidget: Widget {
    let kind: String = "QuestsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuestProvider()) { entry in
            QuestsWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Quests")
        .description("See your daily quests and gold balance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

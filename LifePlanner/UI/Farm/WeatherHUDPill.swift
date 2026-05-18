import SwiftUI
import SwiftData

/// Small pill in the farm overlay showing today's weather. Tapping opens
/// an explainer sheet describing the active modifier.
struct WeatherHUDPill: View {

    let event: DBModel.WeatherEvent?
    let onTap: () -> Void

    private var kind: WeatherKind { event?.kind ?? .clear }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Text(kind.emoji)
                    .font(.system(size: 14))
                Text(kind.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel("\(kind.label) weather today. Tap for details.")
    }
}

// MARK: - Season pill

/// Non-interactive pill showing the current calendar season alongside the
/// weather pill. Purely decorative — no tap action, no modifiers to explain.
struct SeasonHUDPill: View {
    let season: Season

    var body: some View {
        HStack(spacing: 5) {
            Text(season.emoji)
                .font(.system(size: 14))
            Text(season.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel("Current season: \(season.label)")
    }
}

// MARK: - Weather explainer

/// Full explainer sheet shown when the HUD pill is tapped.
struct WeatherExplainerSheet: View {

    @Environment(\.dismiss) private var dismiss
    let event: DBModel.WeatherEvent?

    private var kind: WeatherKind { event?.kind ?? .clear }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(kind.emoji)
                            .font(.system(size: 48))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(kind.label)
                                .font(.title2.bold())
                            Text("Today's weather")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section("Effect") {
                    Text(kind.effectDescription)
                        .foregroundStyle(.secondary)
                }

                if kind != .clear {
                    Section("Modifier") {
                        switch kind {
                        case .sunshine:
                            LabeledContent("Passive gold", value: "+\(FarmTuning.weatherSunshineGold) 🪙 awarded")
                        case .rain:
                            LabeledContent("Habit contribution", value: "×2 today")
                        case .drought:
                            LabeledContent("Task contribution", value: "×0.5 today")
                            LabeledContent("Plot decay", value: "×1.5 today")
                        case .storm:
                            LabeledContent("Storm damage", value: "\(FarmTuning.weatherStormDamage) hp to a random plot")
                        case .clear:
                            EmptyView()
                        }
                    }
                }

                if let event {
                    Section("Duration") {
                        LabeledContent("Expires", value: event.expiresAt, format: .dateTime.hour().minute())
                    }
                }
            }
            .navigationTitle("Today's Weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

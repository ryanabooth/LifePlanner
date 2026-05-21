import SwiftUI

// MARK: - Model

struct GoalTemplate: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let metricUnit: String?
    let metricTarget: Double
    let farmElementType: FarmElementType

    /// Short summary for the picker row.
    var subtitle: String {
        var parts: [String] = []
        if let unit = metricUnit {
            if metricTarget > 0 {
                let formatted = metricTarget.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(metricTarget)) : String(format: "%.0f", metricTarget)
                parts.append("Target: \(formatted) \(unit)")
            } else {
                parts.append("Track: \(unit)")
            }
        }
        return parts.isEmpty ? "Habit-anchored" : parts.joined(separator: " · ")
    }
}

// MARK: - Catalog

enum GoalTemplateCatalog {
    static let all: [GoalTemplate] = [
        GoalTemplate(
            emoji: "🏃",
            title: "Run a 5K",
            metricUnit: "miles",
            metricTarget: 100,
            farmElementType: .crop
        ),
        GoalTemplate(
            emoji: "📚",
            title: "Read 12 books this year",
            metricUnit: "books",
            metricTarget: 12,
            farmElementType: .tree
        ),
        GoalTemplate(
            emoji: "💵",
            title: "Save $5,000",
            metricUnit: "dollars",
            metricTarget: 5000,
            farmElementType: .crop
        ),
        GoalTemplate(
            emoji: "🏋️",
            title: "Build a gym habit",
            metricUnit: nil,
            metricTarget: 0,
            farmElementType: .crop
        ),
        GoalTemplate(
            emoji: "🧘",
            title: "Daily meditation",
            metricUnit: nil,
            metricTarget: 0,
            farmElementType: .crop
        ),
        GoalTemplate(
            emoji: "📝",
            title: "Write a book",
            metricUnit: "words",
            metricTarget: 80000,
            farmElementType: .tree
        ),
        GoalTemplate(
            emoji: "🌐",
            title: "Learn a language",
            metricUnit: "hours",
            metricTarget: 100,
            farmElementType: .crop
        ),
        GoalTemplate(
            emoji: "🎨",
            title: "Daily sketch",
            metricUnit: nil,
            metricTarget: 0,
            farmElementType: .crop
        ),
    ]
}

// MARK: - GoalDraft factory

extension GoalDraft {
    init(from template: GoalTemplate) {
        self.title = template.title
        self.metricUnit = template.metricUnit
        self.metricTarget = template.metricTarget
        self.farmElementType = template.farmElementType
    }
}

// MARK: - Picker sheet

struct GoalTemplatePickerSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext

    /// When set, the nested AddGoalSheet is shown.
    @State private var selectedDraft: GoalDraft?
    /// Flipped to true inside the AddGoalSheet's onSave so onDismiss
    /// can dismiss this whole picker afterwards.
    @State private var goalWasSaved = false

    var body: some View {
        NavigationStack {
            List(GoalTemplateCatalog.all) { template in
                Button {
                    selectedDraft = GoalDraft(from: template)
                } label: {
                    HStack(spacing: 12) {
                        Text(template.emoji)
                            .font(.title2)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(template.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Choose a Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Present AddGoalSheet inside this picker's NavigationStack.
            // When AddGoalSheet saves, it calls its own dismiss(). We track
            // `goalWasSaved` so `onDismiss` can also dismiss this picker.
            .sheet(item: $selectedDraft, onDismiss: {
                if goalWasSaved { dismiss() }
            }) { draft in
                AddGoalSheet(prefilledDraft: draft) { finalDraft in
                    injected.interactors.goals.add(finalDraft, in: modelContext)
                    goalWasSaved = true
                }
            }
        }
    }
}

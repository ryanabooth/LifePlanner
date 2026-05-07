import SwiftUI

struct AddGoalSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var draft: GoalDraft
    @State private var includeTargetDate: Bool
    private let isEditing: Bool
    private let onSave: (GoalDraft) -> Void

    init(existing: DBModel.Goal? = nil, onSave: @escaping (GoalDraft) -> Void) {
        if let existing {
            _draft = State(initialValue: GoalDraft(
                title: existing.title,
                why: existing.why,
                targetDate: existing.targetDate,
                status: existing.status
            ))
            _includeTargetDate = State(initialValue: existing.targetDate != nil)
            isEditing = true
        } else {
            _draft = State(initialValue: GoalDraft())
            _includeTargetDate = State(initialValue: false)
            isEditing = false
        }
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                    TextField("Why does this matter? (optional)", text: Binding(
                        get: { draft.why ?? "" },
                        set: { draft.why = $0 }
                    ), axis: .vertical)
                    .lineLimit(2...6)
                }
                Section {
                    Toggle("Target date", isOn: $includeTargetDate)
                    if includeTargetDate {
                        DatePicker(
                            "Target",
                            selection: Binding(
                                get: { draft.targetDate ?? Date() },
                                set: { draft.targetDate = $0 }
                            ),
                            displayedComponents: [.date]
                        )
                    }
                }
                .onChange(of: includeTargetDate) { _, on in
                    if !on { draft.targetDate = nil }
                    else if draft.targetDate == nil { draft.targetDate = Date() }
                }
                Section("Status") {
                    Picker("Status", selection: $draft.status) {
                        ForEach(GoalStatus.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Goal" : "New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    AddGoalSheet { _ in }
}

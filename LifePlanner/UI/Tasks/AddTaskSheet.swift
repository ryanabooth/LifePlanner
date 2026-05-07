import SwiftUI

struct AddTaskSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var draft: TaskDraft
    @State private var includeDueDate: Bool
    private let isEditing: Bool
    private let onSave: (TaskDraft) -> Void

    init(existing: DBModel.Task? = nil, onSave: @escaping (TaskDraft) -> Void) {
        if let existing {
            _draft = State(initialValue: TaskDraft(
                title: existing.title,
                notes: existing.notes,
                dueDate: existing.dueDate,
                priority: existing.priority,
                tags: existing.tags
            ))
            _includeDueDate = State(initialValue: existing.dueDate != nil)
            isEditing = true
        } else {
            _draft = State(initialValue: TaskDraft())
            _includeDueDate = State(initialValue: false)
            isEditing = false
        }
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                    TextField("Notes (optional)", text: Binding(
                        get: { draft.notes ?? "" },
                        set: { draft.notes = $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                }
                Section {
                    Toggle("Due date", isOn: $includeDueDate)
                    if includeDueDate {
                        DatePicker(
                            "Due",
                            selection: Binding(
                                get: { draft.dueDate ?? Date() },
                                set: { draft.dueDate = $0 }
                            ),
                            displayedComponents: [.date]
                        )
                    }
                }
                .onChange(of: includeDueDate) { _, on in
                    if !on { draft.dueDate = nil }
                    else if draft.dueDate == nil { draft.dueDate = Date() }
                }
                Section("Priority") {
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(TaskPriority.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "New Task")
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
    AddTaskSheet { _ in }
}

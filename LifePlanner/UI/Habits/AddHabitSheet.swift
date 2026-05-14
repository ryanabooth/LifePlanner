import SwiftUI

struct AddHabitSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var draft: HabitDraft
    @State private var includeReminder: Bool
    private let isEditing: Bool
    private let onSave: (HabitDraft) -> Void

    init(existing: DBModel.Habit? = nil, onSave: @escaping (HabitDraft) -> Void) {
        if let existing {
            _draft = State(initialValue: HabitDraft(
                title: existing.title,
                notes: existing.notes,
                frequency: existing.frequency,
                weeklyTarget: existing.weeklyTarget,
                reminderTime: existing.reminderTime
            ))
            _includeReminder = State(initialValue: existing.reminderTime != nil)
            isEditing = true
        } else {
            _draft = State(initialValue: HabitDraft())
            _includeReminder = State(initialValue: false)
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
                    .lineLimit(2...4)
                }
                Section("Frequency") {
                    Picker("Frequency", selection: $draft.frequency) {
                        ForEach(HabitFrequency.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    if draft.frequency == .weekly {
                        Stepper(
                            value: $draft.weeklyTarget,
                            in: 1...7,
                            step: 1
                        ) {
                            Text("Target: \(draft.weeklyTarget)× per week")
                        }
                    }
                }
                Section {
                    Toggle("Daily reminder", isOn: $includeReminder)
                    if includeReminder {
                        DatePicker(
                            "At",
                            selection: Binding(
                                get: { draft.reminderTime ?? defaultReminderTime() },
                                set: { draft.reminderTime = $0 }
                            ),
                            displayedComponents: [.hourAndMinute]
                        )
                    }
                } footer: {
                    if includeReminder {
                        Text("You'll be asked for notification permission the first time you save a reminder.")
                            .font(.footnote)
                    }
                }
                .onChange(of: includeReminder) { _, on in
                    if !on { draft.reminderTime = nil }
                    else if draft.reminderTime == nil { draft.reminderTime = defaultReminderTime() }
                }
            }
            .navigationTitle(isEditing ? "Edit Habit" : "New Habit")
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

    private func defaultReminderTime() -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }
}

#Preview {
    AddHabitSheet { _ in }
}

import SwiftUI
import SwiftData

struct AddHabitSheet: View {

    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\DBModel.Goal.title)])
    private var allGoals: [DBModel.Goal]

    /// Active/paused goals shown in the link picker. Filtered in-memory since
    /// GoalStatus is a Codable enum (no raw Int column for a SwiftData predicate).
    private var linkableGoals: [DBModel.Goal] {
        allGoals.filter { $0.status == .active || $0.status == .paused }
    }

    @State private var draft: HabitDraft
    @State private var includeReminder: Bool
    private let isEditing: Bool
    private let existingHabit: DBModel.Habit?
    private let onSave: (HabitDraft) -> Void

    init(existing: DBModel.Habit? = nil, initialGoalID: UUID? = nil, onSave: @escaping (HabitDraft) -> Void) {
        self.existingHabit = existing
        if let existing {
            _draft = State(initialValue: HabitDraft(
                title: existing.title,
                notes: existing.notes,
                frequency: existing.frequency,
                weeklyTarget: existing.weeklyTarget,
                reminderTime: existing.reminderTime,
                linkedGoalID: existing.goals?.first?.id
            ))
            _includeReminder = State(initialValue: existing.reminderTime != nil)
            isEditing = true
        } else {
            _draft = State(initialValue: HabitDraft(linkedGoalID: initialGoalID))
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
                if !linkableGoals.isEmpty {
                    Section("Goal") {
                        Picker("Link to goal", selection: $draft.linkedGoalID) {
                            Text("None").tag(UUID?.none)
                            ForEach(linkableGoals) { goal in
                                Text(goal.title).tag(UUID?.some(goal.id))
                            }
                        }
                    }
                }
                if let existingHabit {
                    Section("History") {
                        HabitCalendarView(habit: existingHabit)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
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

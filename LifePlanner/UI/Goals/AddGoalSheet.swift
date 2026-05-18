import SwiftUI
import SwiftData

struct AddGoalSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext

    @Query private var plots: [DBModel.FarmPlot]
    @Query private var farmStates: [DBModel.FarmState]

    @State private var draft: GoalDraft
    @State private var includeTargetDate: Bool
    @State private var showCapacityAlert = false
    @State private var showCapacitySheet = false

    private let isEditing: Bool
    private let onSave: (GoalDraft) -> Void

    /// Edit an existing goal, or create a new one (optionally pre-filled from a template).
    init(existing: DBModel.Goal? = nil, prefilledDraft: GoalDraft? = nil, onSave: @escaping (GoalDraft) -> Void) {
        if let existing {
            _draft = State(initialValue: GoalDraft(
                title: existing.title,
                why: existing.why,
                targetDate: existing.targetDate,
                status: existing.status,
                farmElementType: existing.farmElementType,
                metricUnit: existing.metricUnit,
                metricTarget: existing.metricTarget
            ))
            _includeTargetDate = State(initialValue: existing.targetDate != nil)
            _includeMetric = State(initialValue: existing.hasMetric)
            isEditing = true
        } else if let prefilled = prefilledDraft {
            _draft = State(initialValue: prefilled)
            _includeTargetDate = State(initialValue: prefilled.targetDate != nil)
            _includeMetric = State(initialValue: !(prefilled.metricUnit ?? "").isEmpty)
            isEditing = false
        } else {
            _draft = State(initialValue: GoalDraft())
            _includeTargetDate = State(initialValue: false)
            _includeMetric = State(initialValue: false)
            isEditing = false
        }
        self.onSave = onSave
    }

    @State private var includeMetric: Bool = false

    // MARK: - Capacity check

    private var plotCapacity: Int { farmStates.first?.plotCapacity ?? 3 }
    private var usedPlots: Int { plots.filter { $0.kind != .commonField }.count }
    /// True only for new goals at-capacity. Edits never block on capacity because
    /// they re-use the goal's existing plot.
    private var blockedByCapacity: Bool { !isEditing && usedPlots >= plotCapacity }

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

                farmElementSection

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
                Section {
                    Toggle("Track a metric", isOn: $includeMetric)
                    if includeMetric {
                        TextField("Unit (e.g. miles, pages)", text: Binding(
                            get: { draft.metricUnit ?? "" },
                            set: { draft.metricUnit = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        HStack {
                            Text("Target")
                            Spacer()
                            TextField("0", value: $draft.metricTarget, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                        }
                    }
                } footer: {
                    if includeMetric {
                        Text("Set a numeric goal (e.g. \"26.2 miles\"). Leave the target at 0 for an open-ended metric.")
                            .font(.footnote)
                    }
                }
                .onChange(of: includeMetric) { _, on in
                    if !on {
                        draft.metricUnit = nil
                        draft.metricTarget = 0
                    }
                }

                if !draft.subGoalTitles.isEmpty {
                    Section {
                        ForEach(draft.subGoalTitles.indices, id: \.self) { i in
                            Text(draft.subGoalTitles[i])
                        }
                        .onDelete { indexSet in
                            draft.subGoalTitles.remove(atOffsets: indexSet)
                        }
                    } header: {
                        Text("Sub-goals")
                    } footer: {
                        Text("Swipe to remove. Add more from the goal detail view after saving.")
                            .font(.footnote)
                    }
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
                    Button("Save") { attemptSave() }
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Out of plots", isPresented: $showCapacityAlert) {
                Button("Buy plot") { showCapacitySheet = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You're using \(usedPlots) of \(plotCapacity) plots. Expand the farm to add another goal.")
            }
            .sheet(isPresented: $showCapacitySheet) {
                CapacityUpgradeSheet()
            }
        }
    }

    @ViewBuilder
    private var farmElementSection: some View {
        Section {
            if isEditing {
                // Changing element type after a plot is bound would orphan the
                // existing sprite/health; v1 just shows the existing value.
                LabeledContent("Farm element", value: draft.farmElementType.label)
            } else {
                Picker("Farm element", selection: $draft.farmElementType) {
                    ForEach(FarmElementType.allCases.filter(\.isUserSelectable)) { type in
                        Text(type.label).tag(type)
                    }
                }
            }
        } header: {
            Text("Farm element")
        } footer: {
            Text(isEditing
                 ? "Element type is locked once a goal has a farm plot."
                 : "Picks the sprite for this goal's farm plot.")
        }
    }

    // MARK: - Save

    private func attemptSave() {
        if blockedByCapacity {
            showCapacityAlert = true
            return
        }
        onSave(draft)
        dismiss()
    }
}

#Preview {
    AddGoalSheet { _ in }
}

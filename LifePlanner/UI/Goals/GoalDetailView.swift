import SwiftUI
import SwiftData

struct GoalDetailView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var goal: DBModel.Goal

    @Query(sort: [SortDescriptor(\DBModel.Task.createdAt, order: .reverse)])
    private var allTasks: [DBModel.Task]

    @Query(
        filter: #Predicate<DBModel.Habit> { !$0.archived },
        sort: [SortDescriptor(\DBModel.Habit.createdAt, order: .reverse)]
    )
    private var allHabits: [DBModel.Habit]

    @State private var showingEdit = false
    @State private var showingTaskPicker = false
    @State private var showingHabitPicker = false
    @State private var newSubGoalTitle = ""
    @State private var showLogMetric = false
    @State private var logAmount: Double = 1

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Picker("Status", selection: Binding(
                        get: { goal.status },
                        set: { injected.interactors.goals.setStatus(goal, status: $0, in: modelContext) }
                    )) {
                        ForEach(GoalStatus.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                if let date = goal.targetDate {
                    LabeledContent("Target", value: date.formatted(date: .long, time: .omitted))
                }
                if let why = goal.why, !why.isEmpty {
                    Text(why)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if goal.hasMetric {
                metricSection
            }

            subGoalsSection

            Section {
                let linked = goal.linkedTasks ?? []
                if linked.isEmpty {
                    Text("No tasks linked.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(linked) { task in
                        HStack {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isDone ? .green : .secondary)
                            Text(task.title).strikethrough(task.isDone)
                        }
                    }
                }
                Button {
                    showingTaskPicker = true
                } label: {
                    Label("Edit linked tasks", systemImage: "checklist")
                }
            } header: {
                Text("Tasks")
            }

            Section {
                let linked = goal.linkedHabits ?? []
                if linked.isEmpty {
                    Text("No habits linked.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(linked) { habit in
                        Text(habit.title)
                    }
                }
                Button {
                    showingHabitPicker = true
                } label: {
                    Label("Edit linked habits", systemImage: "repeat")
                }
            } header: {
                Text("Habits")
            }

            Section {
                Button("Delete Goal", role: .destructive) {
                    injected.interactors.goals.delete(goal, in: modelContext)
                    dismiss()
                }
            }
        }
        .navigationTitle(goal.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddGoalSheet(existing: goal) { draft in
                injected.interactors.goals.update(goal, with: draft, in: modelContext)
            }
        }
        .sheet(isPresented: $showingTaskPicker) {
            LinkPickerView(
                title: "Link Tasks",
                items: allTasks,
                initiallySelected: Set((goal.linkedTasks ?? []).map(\.id)),
                rowLabel: { Text($0.title) }
            ) { selectedIDs in
                let tasks = allTasks.filter { selectedIDs.contains($0.id) }
                injected.interactors.goals.setLinks(
                    goal,
                    tasks: tasks,
                    habits: goal.linkedHabits ?? [],
                    in: modelContext
                )
            }
        }
        .sheet(isPresented: $showingHabitPicker) {
            LinkPickerView(
                title: "Link Habits",
                items: allHabits,
                initiallySelected: Set((goal.linkedHabits ?? []).map(\.id)),
                rowLabel: { Text($0.title) }
            ) { selectedIDs in
                let habits = allHabits.filter { selectedIDs.contains($0.id) }
                injected.interactors.goals.setLinks(
                    goal,
                    tasks: goal.linkedTasks ?? [],
                    habits: habits,
                    in: modelContext
                )
            }
        }
        .sheet(isPresented: $showLogMetric) {
            LogMetricSheet(
                goal: goal,
                amount: $logAmount,
                onLog: { amount in
                    injected.interactors.goals.logMetricProgress(goal, amount: amount, in: modelContext)
                }
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Sections

    private var subGoalsSection: some View {
        let subs = (goal.subGoals ?? []).sorted { $0.order < $1.order }
        let doneCount = subs.filter(\.isDone).count
        return Section {
            if subs.isEmpty {
                Text("No sub-goals yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(subs) { sub in
                    HStack {
                        Button {
                            injected.interactors.goals.toggleSubGoal(sub, in: modelContext)
                        } label: {
                            Image(systemName: sub.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(sub.isDone ? .green : .secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(sub.isDone ? "Reopen \(sub.title)" : "Complete \(sub.title)")
                        Text(sub.title)
                            .strikethrough(sub.isDone)
                            .foregroundStyle(sub.isDone ? .secondary : .primary)
                            .accessibilityHidden(true)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            injected.interactors.goals.deleteSubGoal(sub, in: modelContext)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            HStack {
                TextField("Add a sub-goal", text: $newSubGoalTitle)
                    .submitLabel(.done)
                    .onSubmit(commitSubGoal)
                Button(action: commitSubGoal) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add sub-goal")
                .disabled(newSubGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            HStack {
                Text("Sub-goals")
                if !subs.isEmpty {
                    Spacer()
                    Text("\(doneCount) / \(subs.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metricSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedValue(goal.metricValue))
                        .font(.title2.bold())
                    Text(goal.metricUnit ?? "")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if goal.metricTarget > 0 {
                        Text("of \(formattedValue(goal.metricTarget))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if goal.metricTarget > 0 {
                    ProgressView(value: goal.metricProgress)
                        .tint(.green)
                        .accessibilityLabel("Progress")
                        .accessibilityValue(
                            "\(formattedValue(goal.metricValue)) of \(formattedValue(goal.metricTarget)) \(goal.metricUnit ?? "")"
                        )
                }
            }
            Button {
                showLogMetric = true
            } label: {
                Label("Log progress", systemImage: "plus.circle")
            }
        } header: {
            Text("Progress")
        }
    }

    private func commitSubGoal() {
        let trimmed = newSubGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        injected.interactors.goals.addSubGoal(trimmed, to: goal, in: modelContext)
        newSubGoalTitle = ""
    }

    private func formattedValue(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(v))
        }
        return String(format: "%.1f", v)
    }
}

private struct LogMetricSheet: View {
    @Environment(\.dismiss) private var dismiss
    let goal: DBModel.Goal
    @Binding var amount: Double
    let onLog: (Double) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Amount", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                        Text(goal.metricUnit ?? "")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Adds to \(goal.title) and pumps health into the plot.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Log progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        onLog(amount)
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
    }
}

private protocol LinkableItem: Identifiable where ID == UUID { }
extension DBModel.Task: LinkableItem { }
extension DBModel.Habit: LinkableItem { }

private struct LinkPickerView<Item: LinkableItem, Label: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let items: [Item]
    @State var selected: Set<UUID>
    let rowLabel: (Item) -> Label
    let onCommit: (Set<UUID>) -> Void

    init(
        title: String,
        items: [Item],
        initiallySelected: Set<UUID>,
        @ViewBuilder rowLabel: @escaping (Item) -> Label,
        onCommit: @escaping (Set<UUID>) -> Void
    ) {
        self.title = title
        self.items = items
        self._selected = State(initialValue: initiallySelected)
        self.rowLabel = rowLabel
        self.onCommit = onCommit
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("Nothing to link yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        let isOn = selected.contains(item.id)
                        Button {
                            if isOn { selected.remove(item.id) } else { selected.insert(item.id) }
                        } label: {
                            HStack {
                                rowLabel(item)
                                Spacer()
                                if isOn {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onCommit(selected)
                        dismiss()
                    }
                }
            }
        }
    }
}

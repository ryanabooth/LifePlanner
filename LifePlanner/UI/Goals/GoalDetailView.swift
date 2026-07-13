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
    @State private var showingNewTask = false
    @State private var showingNewHabit = false
    @State private var showLogMetric = false
    @State private var logAmount: Double = 1

    /// Tasks offered in the link picker: incomplete tasks, plus any already
    /// linked to this goal so they remain selectable for unlinking.
    private var linkableTasks: [DBModel.Task] {
        let linkedIDs = Set((goal.linkedTasks ?? []).map(\.id))
        return allTasks.filter { !$0.isDone || linkedIDs.contains($0.id) }
    }

    /// Linked tasks ordered incomplete-first, then by the shared manual
    /// `sortIndex` (drag-to-reorder), then newest-created.
    private var sortedLinkedTasks: [DBModel.Task] {
        (goal.linkedTasks ?? []).sorted {
            if $0.isDone != $1.isDone { return !$0.isDone }
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            return $0.createdAt > $1.createdAt
        }
    }

    private func moveTasks(from source: IndexSet, to destination: Int) {
        var reordered = sortedLinkedTasks
        reordered.move(fromOffsets: source, toOffset: destination)
        injected.interactors.tasks.setManualOrder(reordered, in: modelContext)
    }

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

            Section {
                let linked = (goal.linkedHabits ?? []).sorted { !$0.isDone(on: Date()) && $1.isDone(on: Date()) }
                if linked.isEmpty {
                    Text("No habits linked.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(linked) { habit in
                        Text(habit.title)
                    }
                }
            } header: {
                sectionHeader(
                    "Habits",
                    linkLabel: "Link existing habit",
                    createLabel: "New habit for this goal",
                    onLink: { showingHabitPicker = true },
                    onCreate: { showingNewHabit = true }
                )
            }

            Section {
                let linked = sortedLinkedTasks
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
                    .onMove(perform: moveTasks)
                }
            } header: {
                sectionHeader(
                    "Tasks",
                    linkLabel: "Link existing task",
                    createLabel: "New task for this goal",
                    onLink: { showingTaskPicker = true },
                    onCreate: { showingNewTask = true }
                )
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
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
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
                items: linkableTasks,
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
        .sheet(isPresented: $showingNewTask) {
            AddTaskSheet(initialGoalID: goal.id) { draft in
                injected.interactors.tasks.add(draft, in: modelContext)
            }
        }
        .sheet(isPresented: $showingNewHabit) {
            AddHabitSheet(initialGoalID: goal.id) { draft in
                injected.interactors.habits.add(draft, in: modelContext)
            }
        }
    }

    // MARK: - Sections

    /// A section header with two trailing quick actions: link an existing item,
    /// and create a new one pre-linked to this goal.
    private func sectionHeader(
        _ title: String,
        linkLabel: String,
        createLabel: String,
        onLink: @escaping () -> Void,
        onCreate: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
            Spacer()
            Button(action: onLink) {
                Image(systemName: "link")
                    .foregroundStyle(.tint)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(linkLabel)
            Button(action: onCreate) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(createLabel)
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

protocol LinkableItem: Identifiable where ID == UUID { }
extension DBModel.Task: LinkableItem { }
extension DBModel.Habit: LinkableItem { }

struct LinkPickerView<Item: LinkableItem, Label: View>: View {
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
                            .contentShape(Rectangle())
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

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

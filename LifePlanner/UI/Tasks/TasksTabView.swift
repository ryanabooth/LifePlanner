import SwiftUI
import SwiftData

struct TasksTabView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext

    @AppStorage("tasks.sortOrder") private var sortOrder: TaskSortOrder = .dueDate
    @State private var showAdd = false
    @State private var editing: DBModel.Task?

    @Query private var allTasks: [DBModel.Task]

    var body: some View {
        NavigationStack {
            TaskListContent(sortOrder: sortOrder, onEdit: { editing = $0 })
                .navigationTitle("Tasks")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        sortMenu
                    }
                }
                .sheet(isPresented: $showAdd) {
                    AddTaskSheet { draft in
                        injected.interactors.tasks.add(draft, in: modelContext)
                    }
                }
                .sheet(item: $editing) { task in
                    AddTaskSheet(existing: task) { draft in
                        injected.interactors.tasks.update(task, with: draft, in: modelContext)
                    }
                }
                .onReceive(injected.appState.updates(for: \.routing.pendingDeepLink)) { target in
                    guard case .task(let id)? = target,
                          let task = allTasks.first(where: { $0.id == id }) else { return }
                    editing = task
                    injected.appState[\.routing.pendingDeepLink] = nil
                }
                // Closing the editor always lands on the Tasks tab. A task-due
                // deep link can present this sheet over whatever tab was front
                // (e.g. the farm); without this, dismissing the form would leave
                // the user stranded there instead of back at their task list.
                .onChange(of: editing) { _, newValue in
                    if newValue == nil {
                        injected.appState[\.routing.selectedTab] = .tasks
                    }
                }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(TaskSortOrder.allCases, id: \.self) { order in
                    Label(order.label, systemImage: order.symbolName).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .accessibilityLabel("Sort tasks")
        }
    }
}

private struct TaskListContent: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext

    // Fetch unsorted; sort in-memory to avoid SwiftData SortDescriptor issues with enum keypaths.
    @Query(filter: #Predicate<DBModel.Task> { !$0.isDone })
    private var openTasksRaw: [DBModel.Task]

    @Query(
        filter: #Predicate<DBModel.Task> { $0.isDone },
        sort: [SortDescriptor(\DBModel.Task.completedAt, order: .reverse)]
    )
    private var doneTasks: [DBModel.Task]

    let sortOrder: TaskSortOrder
    let onEdit: (DBModel.Task) -> Void

    private var openTasks: [DBModel.Task] {
        switch sortOrder {
        case .dueDate:
            openTasksRaw.sorted {
                switch ($0.dueDate, $1.dueDate) {
                case let (a?, b?): return a < b
                case (_?, nil):   return true
                case (nil, _?):   return false
                case (nil, nil):  return $0.createdAt > $1.createdAt
                }
            }
        case .priority:
            openTasksRaw.sorted {
                if $0.priorityRaw != $1.priorityRaw { return $0.priorityRaw > $1.priorityRaw }
                return $0.createdAt > $1.createdAt
            }
        }
    }

    var body: some View {
        if openTasksRaw.isEmpty && doneTasks.isEmpty {
            ContentUnavailableView(
                "No tasks yet",
                systemImage: "checklist",
                description: Text("Tap + to add your first task.")
            )
        } else {
            List {
                if !openTasks.isEmpty {
                    Section("Open") {
                        ForEach(openTasks, id: \.id) { row(for: $0) }
                    }
                }
                if !doneTasks.isEmpty {
                    Section("Done") {
                        ForEach(doneTasks) { row(for: $0) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for task: DBModel.Task) -> some View {
        TaskRow(task: task)
            .contentShape(Rectangle())
            .onTapGesture { onEdit(task) }
            .swipeActions(edge: .leading) {
                Button {
                    if !task.isDone { HapticPlayer.shared.crescendo() }
                    injected.interactors.tasks.toggleDone(task, in: modelContext)
                } label: {
                    Label(task.isDone ? "Reopen" : "Done",
                          systemImage: task.isDone ? "arrow.uturn.left" : "checkmark")
                }
                .tint(task.isDone ? .gray : .green)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    injected.interactors.tasks.delete(task, in: modelContext)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

private struct TaskRow: View {
    let task: DBModel.Task

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: task.priority.symbolName)
                .foregroundStyle(priorityColor)
                .font(.caption.weight(.bold))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(task.title)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                    if task.recurrence != nil {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let due = task.dueDate {
                    Text(due, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        var parts: [String] = []
        parts.append(task.title)
        parts.append("\(task.priority.label) priority")
        if let due = task.dueDate {
            let formatted = due.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            parts.append("due \(formatted)")
        }
        if task.recurrence != nil { parts.append("recurring") }
        if task.isDone { parts.append("completed") }
        return parts.joined(separator: ", ")
    }

    private var priorityColor: Color {
        switch task.priority {
        case .low: return .secondary
        case .normal: return .accentColor
        case .high: return .red
        }
    }
}

#Preview {
    TasksTabView()
        .modelContainer(for: DBModel.Task.self, inMemory: true)
}

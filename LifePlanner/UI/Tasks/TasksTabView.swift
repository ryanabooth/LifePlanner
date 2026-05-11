import SwiftUI
import SwiftData

struct TasksTabView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext

    @AppStorage("tasks.sortOrder") private var sortOrder: TaskSortOrder = .dueDate
    @State private var showAdd = false
    @State private var editing: DBModel.Task?

    var body: some View {
        NavigationStack {
            TaskListContent(sortOrder: sortOrder, onEdit: { editing = $0 })
                .navigationTitle("Tasks")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                    }
                    ToolbarItem(placement: .secondaryAction) {
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
        }
    }
}

private struct TaskListContent: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext

    @Query private var openTasks: [DBModel.Task]
    @Query private var doneTasks: [DBModel.Task]

    let onEdit: (DBModel.Task) -> Void

    init(sortOrder: TaskSortOrder, onEdit: @escaping (DBModel.Task) -> Void) {
        self.onEdit = onEdit
        let openSort: [SortDescriptor<DBModel.Task>]
        switch sortOrder {
        case .dueDate:
            openSort = [
                SortDescriptor(\DBModel.Task.dueDate, order: .forward),
                SortDescriptor(\DBModel.Task.createdAt, order: .reverse)
            ]
        case .priority:
            openSort = [
                SortDescriptor(\DBModel.Task.priority, order: .reverse),
                SortDescriptor(\DBModel.Task.createdAt, order: .reverse)
            ]
        }
        _openTasks = Query(filter: #Predicate<DBModel.Task> { !$0.isDone }, sort: openSort)
        _doneTasks = Query(
            filter: #Predicate<DBModel.Task> { $0.isDone },
            sort: [SortDescriptor(\DBModel.Task.completedAt, order: .reverse)]
        )
    }

    var body: some View {
        if openTasks.isEmpty && doneTasks.isEmpty {
            ContentUnavailableView(
                "No tasks yet",
                systemImage: "checklist",
                description: Text("Tap + to add your first task.")
            )
        } else {
            List {
                if !openTasks.isEmpty {
                    Section("Open") {
                        ForEach(openTasks) { row(for: $0) }
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
                Text(task.title)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                if let due = task.dueDate {
                    Text(due, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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

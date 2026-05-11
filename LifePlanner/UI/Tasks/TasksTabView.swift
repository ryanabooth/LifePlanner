import SwiftUI
import SwiftData

struct TasksTabView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<DBModel.Task> { !$0.isDone },
        sort: [
            SortDescriptor(\DBModel.Task.dueDate, order: .forward),
            SortDescriptor(\DBModel.Task.createdAt, order: .reverse)
        ]
    )
    private var openTasks: [DBModel.Task]

    @Query(
        filter: #Predicate<DBModel.Task> { $0.isDone },
        sort: [SortDescriptor(\DBModel.Task.completedAt, order: .reverse)]
    )
    private var doneTasks: [DBModel.Task]

    @State private var showAdd = false
    @State private var editing: DBModel.Task?

    var body: some View {
        NavigationStack {
            Group {
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
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
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

    @ViewBuilder
    private func row(for task: DBModel.Task) -> some View {
        TaskRow(task: task)
            .contentShape(Rectangle())
            .onTapGesture { editing = task }
            .swipeActions(edge: .leading) {
                Button {
                    injected.interactors.tasks.toggleDone(task, in: modelContext)
                } label: {
                    Label(task.isDone ? "Reopen" : "Done", systemImage: task.isDone ? "arrow.uturn.left" : "checkmark")
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
                    Text(due, format: .dateTime.month(.abbreviated).day().hour().minute())
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

import SwiftUI
import SwiftData

struct HabitsTabView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<DBModel.Habit> { !$0.archived },
        sort: [SortDescriptor(\DBModel.Habit.createdAt, order: .forward)]
    )
    private var activeHabits: [DBModel.Habit]

    @State private var showAdd = false
    @State private var editing: DBModel.Habit?

    var body: some View {
        NavigationStack {
            Group {
                if activeHabits.isEmpty {
                    ContentUnavailableView(
                        "No habits yet",
                        systemImage: "repeat",
                        description: Text("Tap + to add a daily habit.")
                    )
                } else {
                    List {
                        Section("Today") {
                            ForEach(activeHabits) { row(for: $0) }
                        }
                    }
                }
            }
            .navigationTitle("Habits")
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
                AddHabitSheet { draft in
                    injected.interactors.habits.add(draft, in: modelContext)
                }
            }
            .sheet(item: $editing) { habit in
                AddHabitSheet(existing: habit) { draft in
                    injected.interactors.habits.update(habit, with: draft, in: modelContext)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for habit: DBModel.Habit) -> some View {
        HabitRow(habit: habit)
            .contentShape(Rectangle())
            .onTapGesture {
                injected.interactors.habits.toggleDone(habit, on: Date(), in: modelContext)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    injected.interactors.habits.delete(habit, in: modelContext)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    injected.interactors.habits.setArchived(habit, archived: true, in: modelContext)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(.gray)
            }
            .swipeActions(edge: .leading) {
                Button {
                    editing = habit
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
    }
}

private struct HabitRow: View {
    let habit: DBModel.Habit

    var body: some View {
        let done = habit.isDone(on: Date())
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .strikethrough(done)
                    .foregroundStyle(done ? .secondary : .primary)
                Text(habit.frequency.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    HabitsTabView()
        .modelContainer(for: [DBModel.Habit.self, DBModel.HabitLogEntry.self], inMemory: true)
}

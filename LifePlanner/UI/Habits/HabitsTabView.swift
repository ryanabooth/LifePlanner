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
        HabitRow(
            habit: habit,
            onToggle: {
                injected.interactors.habits.toggleDone(habit, on: Date(), in: modelContext)
            },
            onEdit: {
                editing = habit
            }
        )
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
    }
}

private struct HabitRow: View {
    let habit: DBModel.Habit
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let done = habit.isDone(on: Date())
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? .green : .secondary)
                    .contentShape(Rectangle())
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)

            Button(action: onEdit) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.title)
                            .strikethrough(done)
                            .foregroundStyle(done ? .secondary : .primary)
                        HStack(spacing: 6) {
                            Text(habit.frequency.label)
                            if habit.reminderTime != nil {
                                Image(systemName: "bell.fill")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    HabitsTabView()
        .modelContainer(for: [DBModel.Habit.self, DBModel.HabitLogEntry.self], inMemory: true)
}

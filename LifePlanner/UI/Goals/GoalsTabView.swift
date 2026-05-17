import SwiftUI
import SwiftData

struct GoalsTabView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\DBModel.Goal.createdAt, order: .reverse)])
    private var goals: [DBModel.Goal]

    @State private var showAdd = false
    @State private var showTemplatePicker = false

    var body: some View {
        NavigationStack {
            Group {
                if goals.isEmpty {
                    ContentUnavailableView {
                        Label("No goals yet", systemImage: "target")
                    } description: {
                        Text("Goals tie tasks and habits together. Tap + to add one, or start from a template.")
                    } actions: {
                        Button("Add from Template") { showTemplatePicker = true }
                            .buttonStyle(.bordered)
                    }
                } else {
                    List {
                        ForEach(GoalStatus.allCases) { status in
                            let inStatus = goals.filter { $0.status == status }
                            if !inStatus.isEmpty {
                                Section(status.label) {
                                    ForEach(inStatus) { goal in
                                        NavigationLink {
                                            GoalDetailView(goal: goal)
                                        } label: {
                                            GoalRow(goal: goal)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showAdd = true } label: {
                            Label("New Goal", systemImage: "plus")
                        }
                        Button { showTemplatePicker = true } label: {
                            Label("Add from Template", systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddGoalSheet { draft in
                    injected.interactors.goals.add(draft, in: modelContext)
                }
            }
            .sheet(isPresented: $showTemplatePicker) {
                GoalTemplatePickerSheet()
            }
        }
    }
}

private struct GoalRow: View {
    let goal: DBModel.Goal

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: goal.status.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                HStack(spacing: 8) {
                    if let date = goal.targetDate {
                        Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                    let taskCount = (goal.linkedTasks ?? []).count
                    let habitCount = (goal.linkedHabits ?? []).count
                    if taskCount > 0 {
                        Label("\(taskCount)", systemImage: "checklist")
                    }
                    if habitCount > 0 {
                        Label("\(habitCount)", systemImage: "repeat")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    GoalsTabView()
        .modelContainer(for: [
            DBModel.Goal.self, DBModel.Task.self, DBModel.Habit.self, DBModel.HabitLogEntry.self
        ], inMemory: true)
}

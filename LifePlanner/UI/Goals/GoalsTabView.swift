import SwiftUI
import SwiftData

struct GoalsTabView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Query(sort: [SortDescriptor(\DBModel.Goal.createdAt, order: .reverse)])
    private var goals: [DBModel.Goal]

    @State private var showAdd = false
    @State private var showTemplatePicker = false
    @State private var selectedGoal: DBModel.Goal?

    var body: some View {
        if sizeClass == .compact {
            compactView
        } else {
            regularSplitView
        }
    }

    // MARK: - Compact (iPhone) — unchanged push navigation

    private var compactView: some View {
        NavigationStack {
            goalListContent(selectionBinding: nil)
                .navigationTitle("Goals")
                .toolbar { addToolbarItem }
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

    // MARK: - Regular (iPad) — two-pane split

    private var regularSplitView: some View {
        NavigationSplitView {
            goalListContent(selectionBinding: $selectedGoal)
                .navigationTitle("Goals")
                .toolbar { addToolbarItem }
                .sheet(isPresented: $showAdd) {
                    AddGoalSheet { draft in
                        injected.interactors.goals.add(draft, in: modelContext)
                    }
                }
                .sheet(isPresented: $showTemplatePicker) {
                    GoalTemplatePickerSheet()
                }
        } detail: {
            if let goal = selectedGoal {
                GoalDetailView(goal: goal)
            } else {
                ContentUnavailableView("Select a goal", systemImage: "target")
            }
        }
    }

    // MARK: - Shared list content

    /// Builds the goals list.
    /// - Parameter selectionBinding: when non-nil (iPad), rows set the binding instead of pushing via NavigationLink.
    @ViewBuilder
    private func goalListContent(selectionBinding: Binding<DBModel.Goal?>?) -> some View {
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
                List(selection: selectionBinding) {
                    ForEach(GoalStatus.allCases) { status in
                        let inStatus = goals.filter { $0.status == status }
                        if !inStatus.isEmpty {
                            Section(status.label) {
                                ForEach(inStatus) { goal in
                                    if let binding = selectionBinding {
                                        // iPad: tap selects into the detail pane
                                        GoalRow(goal: goal)
                                            .tag(goal)
                                            .contentShape(Rectangle())
                                            .onTapGesture { binding.wrappedValue = goal }
                                    } else {
                                        // iPhone: standard push
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
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var addToolbarItem: some ToolbarContent {
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
                    .accessibilityLabel("Add goal")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        var parts = [goal.title, goal.status.label]
        if let date = goal.targetDate {
            parts.append("due \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        let taskCount = (goal.linkedTasks ?? []).count
        let habitCount = (goal.linkedHabits ?? []).count
        if taskCount > 0 { parts.append("\(taskCount) task\(taskCount == 1 ? "" : "s")") }
        if habitCount > 0 { parts.append("\(habitCount) habit\(habitCount == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    GoalsTabView()
        .modelContainer(for: [
            DBModel.Goal.self, DBModel.Task.self, DBModel.Habit.self, DBModel.HabitLogEntry.self
        ], inMemory: true)
}

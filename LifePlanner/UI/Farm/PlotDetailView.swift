import SwiftUI
import SwiftData

/// Detail view pushed onto the farm's NavigationStack when the user taps a
/// farm plot. Equivalent to the former `PlotDetailSheet` but lives inside the
/// existing NavigationStack so the tab bar reappears for navigation.
struct PlotDetailView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext

    let plotID: UUID

    /// Re-queried by id so SwiftData updates (health change, state transition,
    /// re-plant) reflect immediately while the view is visible.
    @Query private var plots: [DBModel.FarmPlot]
    @Query private var weatherEvents: [DBModel.WeatherEvent]

    @Query(sort: [SortDescriptor(\DBModel.Task.createdAt, order: .reverse)])
    private var allTasks: [DBModel.Task]

    @Query(
        filter: #Predicate<DBModel.Habit> { !$0.archived },
        sort: [SortDescriptor(\DBModel.Habit.createdAt, order: .reverse)]
    )
    private var allHabits: [DBModel.Habit]

    @State private var showEditGoal = false
    @State private var showingTaskPicker = false
    @State private var showingHabitPicker = false
    @State private var showingNewTask = false
    @State private var showingNewHabit = false

    private var activeWeather: DBModel.WeatherEvent? {
        let now = Date()
        return weatherEvents.first { $0.startedAt <= now && $0.expiresAt > now }
    }

    /// Tasks offered in the link picker: incomplete tasks, plus any already
    /// linked to this goal so they remain selectable for unlinking.
    private func linkableTasks(for goal: DBModel.Goal) -> [DBModel.Task] {
        let linkedIDs = Set((goal.linkedTasks ?? []).map(\.id))
        return allTasks.filter { !$0.isDone || linkedIDs.contains($0.id) }
    }

    init(plotID: UUID) {
        self.plotID = plotID
        // Fetch only the row we care about. Predicate can compare UUID directly.
        let id = plotID
        self._plots = Query(
            filter: #Predicate<DBModel.FarmPlot> { $0.id == id }
        )
    }

    private var plot: DBModel.FarmPlot? { plots.first }

    var body: some View {
        Group {
            if let plot {
                content(for: plot)
            } else {
                ContentUnavailableView(
                    "Plot unavailable",
                    systemImage: "leaf",
                    description: Text("This plot was removed.")
                )
            }
        }
        .navigationTitle(plot?.goal?.title ?? "Common Field")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if plot?.goal != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEditGoal = true }
                }
            }
        }
        .sheet(isPresented: $showEditGoal) {
            if let goal = plot?.goal {
                AddGoalSheet(existing: goal) { draft in
                    injected.interactors.goals.update(goal, with: draft, in: modelContext)
                }
            }
        }
        .sheet(isPresented: $showingTaskPicker) {
            if let goal = plot?.goal {
                LinkPickerView(
                    title: "Link Tasks",
                    items: linkableTasks(for: goal),
                    initiallySelected: Set((goal.linkedTasks ?? []).map(\.id)),
                    rowLabel: { Text($0.title) }
                ) { selectedIDs in
                    let tasks = allTasks.filter { selectedIDs.contains($0.id) }
                    injected.interactors.goals.setLinks(
                        goal, tasks: tasks, habits: goal.linkedHabits ?? [], in: modelContext
                    )
                }
            }
        }
        .sheet(isPresented: $showingHabitPicker) {
            if let goal = plot?.goal {
                LinkPickerView(
                    title: "Link Habits",
                    items: allHabits,
                    initiallySelected: Set((goal.linkedHabits ?? []).map(\.id)),
                    rowLabel: { Text($0.title) }
                ) { selectedIDs in
                    let habits = allHabits.filter { selectedIDs.contains($0.id) }
                    injected.interactors.goals.setLinks(
                        goal, tasks: goal.linkedTasks ?? [], habits: habits, in: modelContext
                    )
                }
            }
        }
        .sheet(isPresented: $showingNewTask) {
            if let goal = plot?.goal {
                AddTaskSheet(initialGoalID: goal.id) { draft in
                    injected.interactors.tasks.add(draft, in: modelContext)
                }
            }
        }
        .sheet(isPresented: $showingNewHabit) {
            if let goal = plot?.goal {
                AddHabitSheet(initialGoalID: goal.id) { draft in
                    injected.interactors.habits.add(draft, in: modelContext)
                }
            }
        }
    }

    /// A section header with two trailing quick actions: link an existing item,
    /// and create a new one pre-linked to this goal.
    private func linkSectionHeader(
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

    @ViewBuilder
    private func content(for plot: DBModel.FarmPlot) -> some View {
        Form {
            statsSection(plot: plot)

            if let goal = plot.goal {
                habitsSection(goal: goal)
                tasksSection(goal: goal)
            } else {
                commonFieldHabitsSection
                commonFieldTasksSection
            }

            if plot.state == .dead || plot.state == .withered {
                replantSection(plot: plot)
            }
        }
    }

    private func statsSection(plot: DBModel.FarmPlot) -> some View {
        Section {
            LabeledContent("Kind", value: plot.kind.label)
            LabeledContent("State", value: stateLabel(plot.state))
            LabeledContent("Health", value: "\(plot.health) / 100")
            ProgressView(value: Double(plot.health), total: 100)
                .tint(healthTint(plot.health, state: plot.state))
                .accessibilityLabel("Health")
                .accessibilityValue("\(plot.health) out of 100")
            if let weather = activeWeather, weather.kind != .clear,
               let modifier = weatherModifierText(for: weather.kind, plotKind: plot.kind) {
                LabeledContent("Today", value: modifier)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func weatherModifierText(for kind: WeatherKind, plotKind: FarmElementType) -> String? {
        switch kind {
        case .rain:
            return plotKind == .commonField ? nil : "+100% from rain 🌧"
        case .drought:
            return "–50% task contributions, ×1.5 decay 🔥"
        case .sunshine:
            return plotKind == .commonField ? "Passive gold today ☀️" : nil
        default:
            return nil
        }
    }

    private func tasksSection(goal: DBModel.Goal) -> some View {
        Section {
            let linked = (goal.linkedTasks ?? []).sorted { !$0.isDone && $1.isDone }
            if linked.isEmpty {
                Text("No tasks linked to this goal.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linked) { task in
                    Button {
                        if !task.isDone { HapticPlayer.shared.crescendo() }
                        injected.interactors.tasks.toggleDone(task, in: modelContext)
                    } label: {
                        HStack {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isDone ? .green : .secondary)
                            Text(task.title)
                                .strikethrough(task.isDone)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(task.isDone ? "Reopen \(task.title)" : "Mark complete: \(task.title)")
                }
            }
        } header: {
            linkSectionHeader(
                "Linked tasks",
                linkLabel: "Link existing task",
                createLabel: "New task for this goal",
                onLink: { showingTaskPicker = true },
                onCreate: { showingNewTask = true }
            )
        }
    }

    private func habitsSection(goal: DBModel.Goal) -> some View {
        Section {
            let linked = (goal.linkedHabits ?? []).sorted { !$0.isDone(on: Date()) && $1.isDone(on: Date()) }
            if linked.isEmpty {
                Text("No habits linked to this goal.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linked) { habit in
                    Button {
                        if !habit.isDone(on: Date()) { HapticPlayer.shared.crescendo() }
                        injected.interactors.habits.toggleDone(habit, on: Date(), in: modelContext)
                    } label: {
                        HStack {
                            Image(systemName: habit.isDone(on: Date()) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(habit.isDone(on: Date()) ? .green : .secondary)
                            Text(habit.title)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(habit.isDone(on: Date()) ? "Undo log: \(habit.title)" : "Log habit: \(habit.title)")
                }
            }
        } header: {
            linkSectionHeader(
                "Linked habits",
                linkLabel: "Link existing habit",
                createLabel: "New habit for this goal",
                onLink: { showingHabitPicker = true },
                onCreate: { showingNewHabit = true }
            )
        }
    }

    private var commonFieldHabitsSection: some View {
        let unlinked = allHabits
            .filter { ($0.goals ?? []).isEmpty }
            .sorted { !$0.isDone(on: Date()) && $1.isDone(on: Date()) }
        return Section {
            if unlinked.isEmpty {
                Text("No unlinked habits yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(unlinked) { habit in
                    Button {
                        if !habit.isDone(on: Date()) { HapticPlayer.shared.crescendo() }
                        injected.interactors.habits.toggleDone(habit, on: Date(), in: modelContext)
                    } label: {
                        HStack {
                            Image(systemName: habit.isDone(on: Date()) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(habit.isDone(on: Date()) ? .green : .secondary)
                            Text(habit.title)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(habit.isDone(on: Date()) ? "Undo log: \(habit.title)" : "Log habit: \(habit.title)")
                }
            }
        } header: {
            Text("Habits")
                .font(.footnote)
        } footer: {
            Text("Unlinked habits feed the common field.")
                .font(.footnote)
        }
    }

    private var commonFieldTasksSection: some View {
        let unlinked = allTasks
            .filter { ($0.goals ?? []).isEmpty && !$0.isDone }
            .sorted { !$0.isDone && $1.isDone }
        return Section {
            if unlinked.isEmpty {
                Text("No unlinked tasks yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(unlinked) { task in
                    Button {
                        if !task.isDone { HapticPlayer.shared.crescendo() }
                        injected.interactors.tasks.toggleDone(task, in: modelContext)
                    } label: {
                        HStack {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isDone ? .green : .secondary)
                            Text(task.title)
                                .strikethrough(task.isDone)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(task.isDone ? "Reopen \(task.title)" : "Mark complete: \(task.title)")
                }
            }
        } header: {
            Text("Tasks")
                .font(.footnote)
        } footer: {
            Text("Unlinked tasks feed the common field.")
                .font(.footnote)
        }
    }

    private func replantSection(plot: DBModel.FarmPlot) -> some View {
        Section {
            Button {
                try? injected.interactors.farm.replant(plot, in: modelContext)
            } label: {
                Label("Re-plant (–\(FarmTuning.replantCost) gold)", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(injected.interactors.economy.balance(in: modelContext) < FarmTuning.replantCost)
        } header: {
            Text(plot.state == .dead ? "Plot died" : "Plot is withering")
        } footer: {
            Text("Replanting restores the plot to health \(FarmTuning.initialHealth). The underlying goal is preserved.")
        }
    }

    // MARK: - Helpers

    private func stateLabel(_ state: PlotState) -> String {
        switch state {
        case .empty:    return "Empty"
        case .growing:  return "Growing"
        case .mature:   return "Mature"
        case .withered: return "Withered"
        case .dead:     return "Dead"
        }
    }

    private func healthTint(_ health: Int, state: PlotState) -> Color {
        if state == .dead { return .gray }
        switch health {
        case 70...:   return .green
        case 35..<70: return .yellow
        default:      return .red
        }
    }
}

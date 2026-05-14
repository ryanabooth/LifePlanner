import SwiftUI
import SwiftData

/// Modal presented when the user taps a farm plot. Shows the bound Goal's
/// linked tasks and habits with one-tap completion shortcuts; surfaces
/// re-plant when the plot is dead.
struct PlotDetailSheet: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let plotID: UUID

    /// Re-queried by id so SwiftData updates (health change, state transition,
    /// re-plant) reflect immediately while the sheet is open.
    @Query private var plots: [DBModel.FarmPlot]

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
        NavigationStack {
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func content(for plot: DBModel.FarmPlot) -> some View {
        Form {
            statsSection(plot: plot)

            if let goal = plot.goal {
                tasksSection(goal: goal)
                habitsSection(goal: goal)
            } else {
                Section {
                    Text("The common field is fed by any habit or task you complete that isn't linked to a goal.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if plot.state == .dead {
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
        }
    }

    private func tasksSection(goal: DBModel.Goal) -> some View {
        Section {
            let linked = goal.linkedTasks ?? []
            if linked.isEmpty {
                Text("No tasks linked to this goal.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linked) { task in
                    Button {
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
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Linked tasks")
        }
    }

    private func habitsSection(goal: DBModel.Goal) -> some View {
        Section {
            let linked = goal.linkedHabits ?? []
            if linked.isEmpty {
                Text("No habits linked to this goal.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linked) { habit in
                    Button {
                        injected.interactors.habits.toggleDone(habit, on: Date(), in: modelContext)
                    } label: {
                        HStack {
                            Image(systemName: habit.isDone(on: Date()) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(habit.isDone(on: Date()) ? .green : .secondary)
                            Text(habit.title)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Linked habits")
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
            Text("Plot died")
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

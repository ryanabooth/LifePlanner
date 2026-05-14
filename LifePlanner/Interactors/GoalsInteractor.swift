import Foundation
import SwiftData

struct GoalDraft {
    var title: String = ""
    var why: String? = nil
    var targetDate: Date? = nil
    var status: GoalStatus = .active
    var farmElementType: FarmElementType = .crop
    /// Empty / nil = no metric. Non-empty = track a numeric metric in this unit.
    var metricUnit: String? = nil
    /// 0 = open-ended metric (no completion target).
    var metricTarget: Double = 0
}

protocol GoalsInteractor {
    func add(_ draft: GoalDraft, in context: ModelContext)
    func update(_ goal: DBModel.Goal, with draft: GoalDraft, in context: ModelContext)
    func setStatus(_ goal: DBModel.Goal, status: GoalStatus, in context: ModelContext)
    func delete(_ goal: DBModel.Goal, in context: ModelContext)
    func setLinks(_ goal: DBModel.Goal, tasks: [DBModel.Task], habits: [DBModel.Habit], in context: ModelContext)

    /// Append a new sub-goal at the end of the parent's ordered list.
    func addSubGoal(_ title: String, to goal: DBModel.Goal, in context: ModelContext)
    /// Toggle done state. Going `false → true` pumps health into the parent's plot.
    func toggleSubGoal(_ subGoal: DBModel.SubGoal, in context: ModelContext)
    func deleteSubGoal(_ subGoal: DBModel.SubGoal, in context: ModelContext)

    /// Add `amount` to the goal's metric value. Pumps health into the plot, the
    /// same way logging a habit does. No-op if the goal doesn't have a metric.
    func logMetricProgress(_ goal: DBModel.Goal, amount: Double, in context: ModelContext)
}

final class RealGoalsInteractor: GoalsInteractor {

    private let farm: FarmInteractor

    init(farm: FarmInteractor = StubFarmInteractor()) {
        self.farm = farm
    }

    func add(_ draft: GoalDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let goal = DBModel.Goal(
            title: title,
            why: draft.why?.nilIfBlank,
            targetDate: draft.targetDate,
            status: draft.status,
            farmElementType: draft.farmElementType,
            metricUnit: draft.metricUnit?.nilIfBlank,
            metricTarget: max(0, draft.metricTarget)
        )
        context.insert(goal)
        // Allocate a farm plot. If at capacity, silently skip — Step 7's UI will
        // surface the over-capacity error and prompt for an upgrade.
        try? farm.bindPlot(to: goal, in: context)
        context.saveQuietly()
    }

    func update(_ goal: DBModel.Goal, with draft: GoalDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        goal.title = title
        goal.why = draft.why?.nilIfBlank
        goal.targetDate = draft.targetDate
        goal.status = draft.status
        goal.metricUnit = draft.metricUnit?.nilIfBlank
        goal.metricTarget = max(0, draft.metricTarget)
        // Changing farmElementType after the fact isn't supported in v1; the
        // existing plot keeps its sprite. Picker UI in Step 7 will disable the
        // control for goals that already have a bound plot.
        goal.updatedAt = Date()
        context.saveQuietly()
    }

    func setStatus(_ goal: DBModel.Goal, status: GoalStatus, in context: ModelContext) {
        goal.status = status
        goal.updatedAt = Date()
        context.saveQuietly()
    }

    func delete(_ goal: DBModel.Goal, in context: ModelContext) {
        // Goal.plot has cascade delete rule, so the plot row is cleaned up automatically.
        context.delete(goal)
        context.saveQuietly()
    }

    func setLinks(_ goal: DBModel.Goal, tasks: [DBModel.Task], habits: [DBModel.Habit], in context: ModelContext) {
        goal.linkedTasks = tasks
        goal.linkedHabits = habits
        goal.updatedAt = Date()
        context.saveQuietly()
    }

    // MARK: - Sub-goals

    func addSubGoal(_ title: String, to goal: DBModel.Goal, in context: ModelContext) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (goal.subGoals ?? []).map(\.order).max().map { $0 + 1 } ?? 0
        let sub = DBModel.SubGoal(title: trimmed, order: nextOrder, goal: goal)
        context.insert(sub)
        goal.updatedAt = Date()
        context.saveQuietly()
    }

    func toggleSubGoal(_ subGoal: DBModel.SubGoal, in context: ModelContext) {
        let wasDone = subGoal.isDone
        subGoal.isDone.toggle()
        subGoal.updatedAt = Date()
        // Completion (false → true) pumps health into the parent's plot. Reverting
        // a completion does not refund (consistent with task/habit completion).
        if !wasDone, let parent = subGoal.goal {
            farm.applyContribution(
                amount: FarmTuning.taskBaseContribution,
                toGoals: [parent],
                in: context
            )
            parent.updatedAt = Date()
        }
        context.saveQuietly()
    }

    func deleteSubGoal(_ subGoal: DBModel.SubGoal, in context: ModelContext) {
        subGoal.goal?.updatedAt = Date()
        context.delete(subGoal)
        context.saveQuietly()
    }

    // MARK: - Metric

    func logMetricProgress(_ goal: DBModel.Goal, amount: Double, in context: ModelContext) {
        guard goal.hasMetric, amount > 0 else { return }
        goal.metricValue += amount
        goal.updatedAt = Date()
        farm.applyContribution(
            amount: FarmTuning.habitContribution,
            toGoals: [goal],
            in: context
        )
        context.saveQuietly()
    }
}

final class StubGoalsInteractor: GoalsInteractor {
    func add(_ draft: GoalDraft, in context: ModelContext) {}
    func update(_ goal: DBModel.Goal, with draft: GoalDraft, in context: ModelContext) {}
    func setStatus(_ goal: DBModel.Goal, status: GoalStatus, in context: ModelContext) {}
    func delete(_ goal: DBModel.Goal, in context: ModelContext) {}
    func setLinks(_ goal: DBModel.Goal, tasks: [DBModel.Task], habits: [DBModel.Habit], in context: ModelContext) {}
    func addSubGoal(_ title: String, to goal: DBModel.Goal, in context: ModelContext) {}
    func toggleSubGoal(_ subGoal: DBModel.SubGoal, in context: ModelContext) {}
    func deleteSubGoal(_ subGoal: DBModel.SubGoal, in context: ModelContext) {}
    func logMetricProgress(_ goal: DBModel.Goal, amount: Double, in context: ModelContext) {}
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

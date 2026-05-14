import Foundation
import SwiftData

struct GoalDraft {
    var title: String = ""
    var why: String? = nil
    var targetDate: Date? = nil
    var status: GoalStatus = .active
    var farmElementType: FarmElementType = .crop
}

protocol GoalsInteractor {
    func add(_ draft: GoalDraft, in context: ModelContext)
    func update(_ goal: DBModel.Goal, with draft: GoalDraft, in context: ModelContext)
    func setStatus(_ goal: DBModel.Goal, status: GoalStatus, in context: ModelContext)
    func delete(_ goal: DBModel.Goal, in context: ModelContext)
    func setLinks(_ goal: DBModel.Goal, tasks: [DBModel.Task], habits: [DBModel.Habit], in context: ModelContext)
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
            farmElementType: draft.farmElementType
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
}

final class StubGoalsInteractor: GoalsInteractor {
    func add(_ draft: GoalDraft, in context: ModelContext) {}
    func update(_ goal: DBModel.Goal, with draft: GoalDraft, in context: ModelContext) {}
    func setStatus(_ goal: DBModel.Goal, status: GoalStatus, in context: ModelContext) {}
    func delete(_ goal: DBModel.Goal, in context: ModelContext) {}
    func setLinks(_ goal: DBModel.Goal, tasks: [DBModel.Task], habits: [DBModel.Habit], in context: ModelContext) {}
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

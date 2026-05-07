import Foundation
import SwiftData

struct GoalDraft {
    var title: String = ""
    var why: String? = nil
    var targetDate: Date? = nil
    var status: GoalStatus = .active
}

protocol GoalsInteractor {
    func add(_ draft: GoalDraft, in context: ModelContext)
    func update(_ goal: DBModel.Goal, with draft: GoalDraft, in context: ModelContext)
    func setStatus(_ goal: DBModel.Goal, status: GoalStatus, in context: ModelContext)
    func delete(_ goal: DBModel.Goal, in context: ModelContext)
    func setLinks(_ goal: DBModel.Goal, tasks: [DBModel.Task], habits: [DBModel.Habit], in context: ModelContext)
}

final class RealGoalsInteractor: GoalsInteractor {

    func add(_ draft: GoalDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let goal = DBModel.Goal(
            title: title,
            why: draft.why?.nilIfBlank,
            targetDate: draft.targetDate,
            status: draft.status
        )
        context.insert(goal)
    }

    func update(_ goal: DBModel.Goal, with draft: GoalDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        goal.title = title
        goal.why = draft.why?.nilIfBlank
        goal.targetDate = draft.targetDate
        goal.status = draft.status
        goal.updatedAt = Date()
    }

    func setStatus(_ goal: DBModel.Goal, status: GoalStatus, in context: ModelContext) {
        goal.status = status
        goal.updatedAt = Date()
    }

    func delete(_ goal: DBModel.Goal, in context: ModelContext) {
        context.delete(goal)
    }

    func setLinks(_ goal: DBModel.Goal, tasks: [DBModel.Task], habits: [DBModel.Habit], in context: ModelContext) {
        goal.linkedTasks = tasks
        goal.linkedHabits = habits
        goal.updatedAt = Date()
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

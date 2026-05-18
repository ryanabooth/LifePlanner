import Foundation
import SwiftData

struct TaskDraft {
    var title: String = ""
    var notes: String? = nil
    var dueDate: Date? = nil
    var priority: TaskPriority = .normal
    var tags: [String] = []
    var recurrence: TaskRecurrence? = nil
    /// ID of the single goal this task is linked to, or nil for unlinked.
    var linkedGoalID: UUID? = nil
}

protocol TasksInteractor {
    func add(_ draft: TaskDraft, in context: ModelContext)
    func update(_ task: DBModel.Task, with draft: TaskDraft, in context: ModelContext)
    func toggleDone(_ task: DBModel.Task, in context: ModelContext)
    func delete(_ task: DBModel.Task, in context: ModelContext)
}

final class RealTasksInteractor: TasksInteractor {

    private let calendar: Calendar
    private let scheduler: NotificationScheduler
    private let farm: FarmInteractor
    private let quests: QuestInteractor
    private let achievements: AchievementInteractor

    init(
        calendar: Calendar = .current,
        scheduler: NotificationScheduler = RealNotificationScheduler(),
        farm: FarmInteractor = StubFarmInteractor(),
        quests: QuestInteractor = StubQuestInteractor(),
        achievements: AchievementInteractor = StubAchievementInteractor()
    ) {
        self.calendar = calendar
        self.scheduler = scheduler
        self.farm = farm
        self.quests = quests
        self.achievements = achievements
    }

    func add(_ draft: TaskDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let task = DBModel.Task(
            title: title,
            notes: draft.notes?.nilIfBlank,
            dueDate: draft.dueDate,
            priority: draft.priority,
            tags: draft.tags,
            recurrence: draft.recurrence
        )
        context.insert(task)
        applyGoalLink(draft.linkedGoalID, to: task, in: context)
        syncReminder(id: task.id, title: task.title, dueDate: task.dueDate, isDone: task.isDone)
        Swift.Task.detached { await SpotlightIndexer.shared.index(task: task) }
        quests.refreshTodaysCommonFieldSlots(in: context)
        context.saveQuietly()
    }

    func update(_ task: DBModel.Task, with draft: TaskDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        task.title = title
        task.notes = draft.notes?.nilIfBlank
        task.dueDate = draft.dueDate
        task.priority = draft.priority
        task.tags = draft.tags
        task.recurrence = draft.recurrence
        task.updatedAt = Date()
        applyGoalLink(draft.linkedGoalID, to: task, in: context)
        syncReminder(id: task.id, title: task.title, dueDate: task.dueDate, isDone: task.isDone)
        Swift.Task.detached { await SpotlightIndexer.shared.index(task: task) }
        context.saveQuietly()
    }

    func toggleDone(_ task: DBModel.Task, in context: ModelContext) {
        task.isDone.toggle()
        task.completedAt = task.isDone ? Date() : nil
        task.updatedAt = Date()
        if task.isDone {
            cancelReminder(id: task.id)
            let matured = farm.applyTaskCompletion(task, in: context)
            quests.notifyCompletion(referenceID: task.id, in: context)
            if task.goals?.isEmpty != false { quests.notifyCommonFieldTend(in: context) }
            quests.checkFarmQuests(in: context)
            quests.trackMatureTransitions(count: matured, in: context)
            achievements.checkAll(in: context)
            let id = task.id
            Swift.Task.detached { await SpotlightIndexer.shared.remove(taskID: id) }
            if let recurrence = task.recurrence, let dueDate = task.dueDate {
                spawnNextOccurrence(of: task, recurrence: recurrence, from: dueDate, in: context)
            }
        } else {
            syncReminder(id: task.id, title: task.title, dueDate: task.dueDate, isDone: false)
            Swift.Task.detached { await SpotlightIndexer.shared.index(task: task) }
        }
        context.saveQuietly()
    }

    func delete(_ task: DBModel.Task, in context: ModelContext) {
        cancelReminder(id: task.id)
        let id = task.id
        Swift.Task.detached { await SpotlightIndexer.shared.remove(taskID: id) }
        context.delete(task)
        context.saveQuietly()
    }

    /// Sets `task.goals` to the single goal matching `goalID`, or clears it when
    /// `goalID` is nil. The many-to-many inverse on `Goal.linkedTasks` is updated
    /// automatically by SwiftData.
    private func applyGoalLink(_ goalID: UUID?, to task: DBModel.Task, in context: ModelContext) {
        guard let goalID else {
            task.goals = []
            return
        }
        let descriptor = FetchDescriptor<DBModel.Goal>(predicate: #Predicate { $0.id == goalID })
        if let goal = try? context.fetch(descriptor).first {
            task.goals = [goal]
        }
    }

    private func spawnNextOccurrence(of task: DBModel.Task, recurrence: TaskRecurrence, from dueDate: Date, in context: ModelContext) {
        let nextDue = recurrence.nextDate(after: dueDate, calendar: calendar)
        let next = DBModel.Task(
            title: task.title,
            notes: task.notes,
            dueDate: nextDue,
            priority: task.priority,
            tags: task.tags,
            recurrence: recurrence
        )
        context.insert(next)
        if let linkedGoals = task.goals, !linkedGoals.isEmpty {
            next.goals = linkedGoals
        }
        syncReminder(id: next.id, title: next.title, dueDate: next.dueDate, isDone: false)
        Swift.Task.detached { await SpotlightIndexer.shared.index(task: next) }
        quests.refreshTodaysCommonFieldSlots(in: context)
    }

    private func syncReminder(id: UUID, title: String, dueDate: Date?, isDone: Bool) {
        guard !isDone, let fireDate = dueDate else {
            cancelReminder(id: id)
            return
        }
        Swift.Task.detached { [scheduler] in
            await scheduler.scheduleTaskDue(taskID: id, title: title, at: fireDate)
        }
    }

    private func cancelReminder(id: UUID) {
        Swift.Task.detached { [scheduler] in
            await scheduler.cancelTaskDue(taskID: id)
        }
    }
}

final class StubTasksInteractor: TasksInteractor {
    func add(_ draft: TaskDraft, in context: ModelContext) {}
    func update(_ task: DBModel.Task, with draft: TaskDraft, in context: ModelContext) {}
    func toggleDone(_ task: DBModel.Task, in context: ModelContext) {}
    func delete(_ task: DBModel.Task, in context: ModelContext) {}
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

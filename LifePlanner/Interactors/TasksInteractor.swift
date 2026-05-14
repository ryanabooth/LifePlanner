import Foundation
import SwiftData

struct TaskDraft {
    var title: String = ""
    var notes: String? = nil
    var dueDate: Date? = nil
    var priority: TaskPriority = .normal
    var tags: [String] = []
}

protocol TasksInteractor {
    func add(_ draft: TaskDraft, in context: ModelContext)
    func update(_ task: DBModel.Task, with draft: TaskDraft, in context: ModelContext)
    func toggleDone(_ task: DBModel.Task, in context: ModelContext)
    func delete(_ task: DBModel.Task, in context: ModelContext)
}

final class RealTasksInteractor: TasksInteractor {

    private let scheduler: NotificationScheduler
    private let farm: FarmInteractor
    private let quests: QuestInteractor

    init(
        scheduler: NotificationScheduler = RealNotificationScheduler(),
        farm: FarmInteractor = StubFarmInteractor(),
        quests: QuestInteractor = StubQuestInteractor()
    ) {
        self.scheduler = scheduler
        self.farm = farm
        self.quests = quests
    }

    func add(_ draft: TaskDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let task = DBModel.Task(
            title: title,
            notes: draft.notes?.nilIfBlank,
            dueDate: draft.dueDate,
            priority: draft.priority,
            tags: draft.tags
        )
        context.insert(task)
        syncReminder(id: task.id, title: task.title, dueDate: task.dueDate, isDone: task.isDone)
    }

    func update(_ task: DBModel.Task, with draft: TaskDraft, in context: ModelContext) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        task.title = title
        task.notes = draft.notes?.nilIfBlank
        task.dueDate = draft.dueDate
        task.priority = draft.priority
        task.tags = draft.tags
        task.updatedAt = Date()
        syncReminder(id: task.id, title: task.title, dueDate: task.dueDate, isDone: task.isDone)
    }

    func toggleDone(_ task: DBModel.Task, in context: ModelContext) {
        task.isDone.toggle()
        task.completedAt = task.isDone ? Date() : nil
        task.updatedAt = Date()
        if task.isDone {
            cancelReminder(id: task.id)
            farm.applyTaskCompletion(task, in: context)
            quests.notifyCompletion(referenceID: task.id, in: context)
        } else {
            syncReminder(id: task.id, title: task.title, dueDate: task.dueDate, isDone: false)
        }
    }

    func delete(_ task: DBModel.Task, in context: ModelContext) {
        cancelReminder(id: task.id)
        context.delete(task)
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

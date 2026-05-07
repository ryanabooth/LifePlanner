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
    }

    func toggleDone(_ task: DBModel.Task, in context: ModelContext) {
        task.isDone.toggle()
        task.completedAt = task.isDone ? Date() : nil
        task.updatedAt = Date()
    }

    func delete(_ task: DBModel.Task, in context: ModelContext) {
        context.delete(task)
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

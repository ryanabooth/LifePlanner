import CoreSpotlight
import SwiftData
import UniformTypeIdentifiers

/// Keeps the CoreSpotlight index in sync with open tasks.
/// All writes are fire-and-forget — Spotlight indexing failures are non-fatal.
actor SpotlightIndexer {

    static let shared = SpotlightIndexer()

    private let domain = "com.lifeplanner.tasks"
    private let index = CSSearchableIndex.default()

    func index(task: DBModel.Task) {
        guard !task.isDone else { return }
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        attrs.title = task.title
        attrs.contentDescription = task.notes
        attrs.keywords = task.tags.isEmpty ? nil : task.tags
        if let due = task.dueDate {
            attrs.dueDate = due
        }
        let item = CSSearchableItem(
            uniqueIdentifier: task.id.uuidString,
            domainIdentifier: domain,
            attributeSet: attrs
        )
        index.indexSearchableItems([item]) { _ in }
    }

    func remove(taskID: UUID) {
        index.deleteSearchableItems(withIdentifiers: [taskID.uuidString]) { _ in }
    }

    func reindexAll(in context: ModelContext) {
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { [weak self] _ in
            guard let self else { return }
            Task {
                let openTasks = (try? context.fetch(FetchDescriptor<DBModel.Task>(
                    predicate: #Predicate { !$0.isDone }
                ))) ?? []
                for task in openTasks {
                    await self.index(task: task)
                }
            }
        }
    }
}

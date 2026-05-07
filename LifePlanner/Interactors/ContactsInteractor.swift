import Foundation
import SwiftData

struct ContactEnrichmentDraft {
    var notes: String? = nil
    var tags: [String] = []
}

protocol ContactsInteractor {
    func enrichment(for systemID: String, displayName: String, in context: ModelContext) -> DBModel.Contact?
    func upsertEnrichment(systemID: String, displayName: String, draft: ContactEnrichmentDraft, in context: ModelContext) -> DBModel.Contact
    func recordInteraction(systemID: String, displayName: String, at date: Date, in context: ModelContext)
    func deleteEnrichment(_ contact: DBModel.Contact, in context: ModelContext)
}

final class RealContactsInteractor: ContactsInteractor {

    func enrichment(for systemID: String, displayName: String, in context: ModelContext) -> DBModel.Contact? {
        guard !systemID.isEmpty else { return nil }
        var fetch = FetchDescriptor<DBModel.Contact>(
            predicate: #Predicate { $0.systemIdentifier == systemID }
        )
        fetch.fetchLimit = 1
        return try? context.fetch(fetch).first
    }

    func upsertEnrichment(systemID: String, displayName: String, draft: ContactEnrichmentDraft, in context: ModelContext) -> DBModel.Contact {
        let trimmedNotes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedTags = draft.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let existing = enrichment(for: systemID, displayName: displayName, in: context) {
            existing.displayNameCache = displayName
            existing.notes = trimmedNotes
            existing.tags = trimmedTags
            existing.updatedAt = Date()
            return existing
        }
        let new = DBModel.Contact(
            systemIdentifier: systemID,
            displayNameCache: displayName,
            notes: trimmedNotes,
            tags: trimmedTags
        )
        context.insert(new)
        return new
    }

    func recordInteraction(systemID: String, displayName: String, at date: Date, in context: ModelContext) {
        guard !systemID.isEmpty else { return }
        if let existing = enrichment(for: systemID, displayName: displayName, in: context) {
            existing.lastInteraction = date
            existing.displayNameCache = displayName
            existing.updatedAt = Date()
        } else {
            let new = DBModel.Contact(
                systemIdentifier: systemID,
                displayNameCache: displayName,
                lastInteraction: date
            )
            context.insert(new)
        }
    }

    func deleteEnrichment(_ contact: DBModel.Contact, in context: ModelContext) {
        context.delete(contact)
    }
}

final class StubContactsInteractor: ContactsInteractor {
    func enrichment(for systemID: String, displayName: String, in context: ModelContext) -> DBModel.Contact? { nil }
    func upsertEnrichment(systemID: String, displayName: String, draft: ContactEnrichmentDraft, in context: ModelContext) -> DBModel.Contact {
        DBModel.Contact(systemIdentifier: systemID, displayNameCache: displayName)
    }
    func recordInteraction(systemID: String, displayName: String, at date: Date, in context: ModelContext) {}
    func deleteEnrichment(_ contact: DBModel.Contact, in context: ModelContext) {}
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

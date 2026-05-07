import Foundation
import SwiftData

extension DBModel {
    @Model
    final class Contact {
        var id: UUID = UUID()
        var systemIdentifier: String = ""
        var displayNameCache: String = ""
        var notes: String? = nil
        var tags: [String] = []
        var lastInteraction: Date? = nil
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(
            id: UUID = UUID(),
            systemIdentifier: String = "",
            displayNameCache: String = "",
            notes: String? = nil,
            tags: [String] = [],
            lastInteraction: Date? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.systemIdentifier = systemIdentifier
            self.displayNameCache = displayNameCache
            self.notes = notes
            self.tags = tags
            self.lastInteraction = lastInteraction
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        var hasEnrichment: Bool {
            !(notes ?? "").isEmpty || !tags.isEmpty || lastInteraction != nil
        }
    }
}

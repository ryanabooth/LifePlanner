import AppIntents
import SwiftData

/// Represents a single non-archived habit for use as an App Intent parameter.
struct HabitEntity: AppEntity {

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Habit")
    static let defaultQuery = HabitEntityQuery()

    /// UUID stored as String — all App Intents ID types must be `EntityIdentifierConvertible`.
    var id: String
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: title))
    }
}

struct HabitEntityQuery: EntityStringQuery {

    func entities(for identifiers: [String]) async throws -> [HabitEntity] {
        let container = try ModelContainer.appModelContainer()
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<DBModel.Habit>(
            predicate: #Predicate { !$0.archived }
        ))) ?? []
        let set = Set(identifiers)
        return all
            .filter { set.contains($0.id.uuidString) }
            .map { HabitEntity(id: $0.id.uuidString, title: $0.title) }
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        let container = try ModelContainer.appModelContainer()
        let context = ModelContext(container)
        return (try? context.fetch(FetchDescriptor<DBModel.Habit>(
            predicate: #Predicate { !$0.archived },
            sortBy: [SortDescriptor(\DBModel.Habit.title)]
        )))?.map { HabitEntity(id: $0.id.uuidString, title: $0.title) } ?? []
    }

    func entities(matching string: String) async throws -> [HabitEntity] {
        try await suggestedEntities()
            .filter { $0.title.localizedCaseInsensitiveContains(string) }
    }
}

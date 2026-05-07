import SwiftData

extension ModelContainer {

    static func appModelContainer(
        inMemoryOnly: Bool = false, isStub: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema.appSchema
        let configuration = ModelConfiguration(
            isStub ? "stub" : nil,
            schema: schema,
            isStoredInMemoryOnly: inMemoryOnly)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static var stub: ModelContainer {
        try! appModelContainer(inMemoryOnly: true, isStub: true)
    }

    var isStub: Bool {
        configurations.first?.name == "stub"
    }
}

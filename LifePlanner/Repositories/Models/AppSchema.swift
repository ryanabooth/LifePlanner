import SwiftData

enum DBModel { }

@Model
final class SchemaPlaceholder {
    var marker: String = ""
    init(marker: String = "") { self.marker = marker }
}

extension Schema {
    private static var actualVersion: Schema.Version = Version(0, 1, 0)

    static var appSchema: Schema {
        Schema([
            SchemaPlaceholder.self
        ], version: actualVersion)
    }
}

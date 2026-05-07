import SwiftData

enum DBModel { }

extension Schema {
    private static var actualVersion: Schema.Version = Version(0, 1, 0)

    static var appSchema: Schema {
        Schema([
            DBModel.Task.self
        ], version: actualVersion)
    }
}

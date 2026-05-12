import SwiftData

enum DBModel { }

extension Schema {
    private static var actualVersion: Schema.Version = Version(0, 5, 0)

    static var appSchema: Schema {
        Schema([
            DBModel.Task.self,
            DBModel.Habit.self,
            DBModel.HabitLogEntry.self,
            DBModel.Goal.self
        ], version: actualVersion)
    }
}

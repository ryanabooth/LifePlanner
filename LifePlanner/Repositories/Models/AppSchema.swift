import SwiftData

enum DBModel { }

extension Schema {
    private static var actualVersion: Schema.Version = Version(0, 8, 0)

    static var appSchema: Schema {
        Schema([
            DBModel.Task.self,
            DBModel.Habit.self,
            DBModel.HabitLogEntry.self,
            DBModel.Goal.self,
            DBModel.FarmState.self,
            DBModel.FarmPlot.self,
            DBModel.Quest.self,
            DBModel.OwnedCosmetic.self
        ], version: actualVersion)
    }
}

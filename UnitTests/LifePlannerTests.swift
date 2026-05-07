import XCTest
import SwiftData
@testable import LifePlanner

final class LifePlannerTests: XCTestCase {

    func test_appStateDefaults() {
        let state = AppState()
        XCTAssertEqual(state.routing.selectedTab, .tasks)
        XCTAssertEqual(state.permissions.notifications, .unknown)
    }

    @MainActor
    func test_tasksInteractor_addAndToggle() throws {
        let container = try ModelContainer(
            for: DBModel.Task.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let interactor = RealTasksInteractor()

        interactor.add(TaskDraft(title: "Buy milk", priority: .high), in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<DBModel.Task>())
        XCTAssertEqual(all.count, 1)
        let task = try XCTUnwrap(all.first)
        XCTAssertEqual(task.title, "Buy milk")
        XCTAssertEqual(task.priority, .high)
        XCTAssertFalse(task.isDone)

        interactor.toggleDone(task, in: context)
        XCTAssertTrue(task.isDone)
        XCTAssertNotNil(task.completedAt)

        interactor.delete(task, in: context)
        try context.save()
        let after = try context.fetch(FetchDescriptor<DBModel.Task>())
        XCTAssertTrue(after.isEmpty)
    }

    @MainActor
    func test_tasksInteractor_rejectsBlankTitle() throws {
        let container = try ModelContainer(
            for: DBModel.Task.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let interactor = RealTasksInteractor()

        interactor.add(TaskDraft(title: "   "), in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<DBModel.Task>())
        XCTAssertTrue(all.isEmpty)
    }
}

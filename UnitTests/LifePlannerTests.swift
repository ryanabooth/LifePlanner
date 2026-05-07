import XCTest
import SwiftData
@testable import LifePlanner

actor FakeNotificationScheduler: NotificationScheduler {
    private(set) var scheduled: [(id: UUID, title: String, time: Date)] = []
    private(set) var cancelled: [UUID] = []

    func scheduleHabitReminder(habitID: UUID, title: String, time: Date) async {
        scheduled.append((habitID, title, time))
    }

    func cancelHabitReminder(habitID: UUID) async {
        cancelled.append(habitID)
    }
}

extension FakeNotificationScheduler {
    func wait(for predicate: @Sendable (FakeNotificationScheduler) async -> Bool, timeout: TimeInterval = 1.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate(self) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

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

    @MainActor
    func test_habitsInteractor_addAndToggleToday() throws {
        let container = try ModelContainer(
            for: DBModel.Habit.self, DBModel.HabitLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let interactor = RealHabitsInteractor(scheduler: StubNotificationScheduler())

        interactor.add(HabitDraft(title: "Read 10 pages"), in: context)
        try context.save()

        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)
        XCTAssertFalse(habit.isDone(on: Date()))

        interactor.toggleDone(habit, on: Date(), in: context)
        try context.save()
        XCTAssertTrue(habit.isDone(on: Date()))
        XCTAssertEqual((habit.entries ?? []).count, 1)

        // Toggling again should remove today's entry.
        interactor.toggleDone(habit, on: Date(), in: context)
        try context.save()
        XCTAssertFalse(habit.isDone(on: Date()))
        XCTAssertEqual((habit.entries ?? []).count, 0)
    }

    @MainActor
    func test_goalsInteractor_linkUnlink() throws {
        let container = try ModelContainer(
            for: DBModel.Goal.self, DBModel.Task.self, DBModel.Habit.self, DBModel.HabitLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let goals = RealGoalsInteractor()
        let tasks = RealTasksInteractor()
        let habits = RealHabitsInteractor()

        goals.add(GoalDraft(title: "Read 24 books"), in: context)
        tasks.add(TaskDraft(title: "Buy book A"), in: context)
        tasks.add(TaskDraft(title: "Buy book B"), in: context)
        habits.add(HabitDraft(title: "Read 10 pages"), in: context)
        try context.save()

        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Goal>()).first)
        let allTasks = try context.fetch(FetchDescriptor<DBModel.Task>())
        let allHabits = try context.fetch(FetchDescriptor<DBModel.Habit>())
        XCTAssertEqual(allTasks.count, 2)

        goals.setLinks(goal, tasks: allTasks, habits: allHabits, in: context)
        try context.save()

        XCTAssertEqual((goal.linkedTasks ?? []).count, 2)
        XCTAssertEqual((goal.linkedHabits ?? []).count, 1)
        // Inverse populated.
        XCTAssertTrue((allTasks[0].goals ?? []).contains { $0.id == goal.id })
        XCTAssertTrue((allHabits[0].goals ?? []).contains { $0.id == goal.id })

        // Drop one task and the habit.
        goals.setLinks(goal, tasks: [allTasks[0]], habits: [], in: context)
        try context.save()
        XCTAssertEqual((goal.linkedTasks ?? []).count, 1)
        XCTAssertEqual((goal.linkedHabits ?? []).count, 0)
    }

    @MainActor
    func test_habitsInteractor_schedulesAndCancelsReminders() async throws {
        let container = try ModelContainer(
            for: DBModel.Habit.self, DBModel.HabitLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let scheduler = FakeNotificationScheduler()
        let interactor = RealHabitsInteractor(scheduler: scheduler)

        let reminderTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!

        // Add with reminder -> schedule fires.
        interactor.add(HabitDraft(title: "Stretch", reminderTime: reminderTime), in: context)
        try context.save()
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)
        await scheduler.wait { await !$0.scheduled.isEmpty }
        let scheduledNow = await scheduler.scheduled
        XCTAssertEqual(scheduledNow.count, 1)
        XCTAssertEqual(scheduledNow.first?.id, habit.id)
        XCTAssertEqual(scheduledNow.first?.title, "Stretch")

        // Update to clear reminder -> cancel fires.
        interactor.update(habit, with: HabitDraft(title: "Stretch", reminderTime: nil), in: context)
        try context.save()
        await scheduler.wait { await !$0.cancelled.isEmpty }
        let cancelledNow = await scheduler.cancelled
        XCTAssertEqual(cancelledNow.last, habit.id)

        // Delete -> cancel fires again.
        interactor.delete(habit, in: context)
        try context.save()
        await scheduler.wait { await $0.cancelled.count >= 2 }
        let cancelledAfter = await scheduler.cancelled
        XCTAssertEqual(cancelledAfter.count, 2)
        XCTAssertTrue(cancelledAfter.allSatisfy { $0 == habit.id })
    }

    @MainActor
    func test_contactsInteractor_upsertEnrichment() throws {
        let container = try ModelContainer(
            for: DBModel.Contact.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let interactor = RealContactsInteractor()

        let first = interactor.upsertEnrichment(
            systemID: "sys-123",
            displayName: "Ada Lovelace",
            draft: ContactEnrichmentDraft(notes: "Mathematician.", tags: ["math", "history"]),
            in: context
        )
        try context.save()

        XCTAssertEqual(first.notes, "Mathematician.")
        XCTAssertEqual(first.tags, ["math", "history"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<DBModel.Contact>()).count, 1)

        let second = interactor.upsertEnrichment(
            systemID: "sys-123",
            displayName: "Ada Lovelace",
            draft: ContactEnrichmentDraft(notes: "First programmer.", tags: ["math"]),
            in: context
        )
        try context.save()
        XCTAssertEqual(second.id, first.id, "Should reuse the existing enrichment row")
        XCTAssertEqual(second.notes, "First programmer.")
        XCTAssertEqual(second.tags, ["math"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<DBModel.Contact>()).count, 1)

        interactor.recordInteraction(systemID: "sys-123", displayName: "Ada Lovelace", at: Date(), in: context)
        XCTAssertNotNil(second.lastInteraction)

        interactor.deleteEnrichment(second, in: context)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<DBModel.Contact>()).isEmpty)
    }

    @MainActor
    func test_contactsInteractor_recordInteractionCreatesRowWhenAbsent() throws {
        let container = try ModelContainer(
            for: DBModel.Contact.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let interactor = RealContactsInteractor()

        interactor.recordInteraction(systemID: "abc", displayName: "Grace Hopper", at: Date(), in: context)
        try context.save()
        let rows = try context.fetch(FetchDescriptor<DBModel.Contact>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.displayNameCache, "Grace Hopper")
        XCTAssertNotNil(rows.first?.lastInteraction)
    }

    @MainActor
    func test_habitsInteractor_archiveAndDelete() throws {
        let container = try ModelContainer(
            for: DBModel.Habit.self, DBModel.HabitLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let interactor = RealHabitsInteractor(scheduler: StubNotificationScheduler())

        interactor.add(HabitDraft(title: "Stretch"), in: context)
        try context.save()

        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)
        interactor.setArchived(habit, archived: true, in: context)
        try context.save()
        XCTAssertTrue(habit.archived)

        interactor.delete(habit, in: context)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<DBModel.Habit>()).isEmpty)
    }
}

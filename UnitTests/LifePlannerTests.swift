import XCTest
import SwiftData
@testable import LifePlanner

actor FakeNotificationScheduler: NotificationScheduler {
    private(set) var scheduled: [(id: UUID, title: String, time: Date)] = []
    private(set) var cancelled: [UUID] = []
    private(set) var scheduledTasks: [(id: UUID, title: String, fireDate: Date)] = []
    private(set) var cancelledTasks: [UUID] = []
    private(set) var plotAlerts: [(id: UUID, title: String)] = []
    private(set) var cancelledPlots: [UUID] = []
    private(set) var streakMilestones: [(habitTitle: String, streak: Int, bonus: Int)] = []

    func scheduleHabitReminder(habitID: UUID, title: String, time: Date, weekdaysOnly: Bool) async {
        scheduled.append((habitID, title, time))
    }

    func cancelHabitReminder(habitID: UUID) async {
        cancelled.append(habitID)
    }

    func reconcileHabitReminders(active: [HabitReminderInfo]) async {
        for habit in active { scheduled.append((habit.id, habit.title, habit.time)) }
    }

    func scheduleTaskDue(taskID: UUID, title: String, at fireDate: Date) async {
        scheduledTasks.append((taskID, title, fireDate))
    }

    func cancelTaskDue(taskID: UUID) async {
        cancelledTasks.append(taskID)
    }

    private(set) var endOfDayReminderTimes: [Date] = []
    private(set) var endOfDayCancelled = false

    func scheduleEndOfDayReminder(at time: Date) async {
        endOfDayReminderTimes.append(time)
    }

    func cancelEndOfDayReminder() async {
        endOfDayCancelled = true
    }

    func schedulePlotAlert(plotID: UUID, title: String, body: String, fireAt: Date) async {
        plotAlerts.append((plotID, title))
    }

    func cancelPlotAlert(plotID: UUID) async {
        cancelledPlots.append(plotID)
    }

    func scheduleStreakMilestone(habitTitle: String, streak: Int, bonus: Int) async {
        streakMilestones.append((habitTitle, streak, bonus))
    }

    private(set) var unlockedAchievements: [(emoji: String, title: String)] = []

    func scheduleAchievementUnlocked(emoji: String, title: String) async {
        unlockedAchievements.append((emoji, title))
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
        XCTAssertEqual(state.routing.selectedTab, .farm)
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

    // MARK: - Economy + Farm

    @MainActor
    func test_deepLink_parsesNotificationIdentifiers() {
        let id = UUID()
        XCTAssertEqual(
            DeepLink(notificationIdentifier: "habit-reminder-\(id.uuidString)"),
            .habit(id))
        // Weekday-variant identifier (…-wd<n>) still resolves to the same habit.
        XCTAssertEqual(
            DeepLink(notificationIdentifier: "habit-reminder-\(id.uuidString)-wd3"),
            .habit(id))
        XCTAssertEqual(
            DeepLink(notificationIdentifier: "task-due-\(id.uuidString)"),
            .task(id))
        XCTAssertEqual(
            DeepLink(notificationIdentifier: "plot-alert-\(id.uuidString)"),
            .farm)
        // Unknown / informational identifiers don't produce a deep link.
        XCTAssertNil(DeepLink(notificationIdentifier: "streak-milestone"))
        XCTAssertNil(DeepLink(notificationIdentifier: "habit-reminder-not-a-uuid"))
    }

    private func makeFarmContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: DBModel.FarmState.self, DBModel.FarmPlot.self, DBModel.Goal.self,
                DBModel.Task.self, DBModel.Habit.self, DBModel.HabitLogEntry.self,
                DBModel.Quest.self, DBModel.WeatherEvent.self,
                DBModel.Achievement.self, DBModel.OwnedTool.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @MainActor
    func test_economy_creditAndSpend() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)
        let economy = RealEconomyInteractor()

        // Bootstrap seeds 100 starting gold.
        XCTAssertEqual(economy.balance(in: context), 100)
        economy.credit(50, reason: "test", in: context)
        XCTAssertEqual(economy.balance(in: context), 150)

        try economy.spend(20, reason: "test", in: context)
        XCTAssertEqual(economy.balance(in: context), 130)

        XCTAssertThrowsError(try economy.spend(9999, reason: "test", in: context)) { error in
            guard case EconomyError.insufficientGold(let have, let need) = error else {
                return XCTFail("expected insufficientGold, got \(error)")
            }
            XCTAssertEqual(have, 130)
            XCTAssertEqual(need, 9999)
        }
        XCTAssertEqual(economy.balance(in: context), 130, "balance unchanged on failed spend")
    }

    @MainActor
    func test_farm_bootstrapIsIdempotent() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)
        farm.bootstrap(in: context)
        farm.bootstrap(in: context)

        let states = try context.fetch(FetchDescriptor<DBModel.FarmState>())
        XCTAssertEqual(states.count, 1, "exactly one FarmState row")

        let plots = try context.fetch(FetchDescriptor<DBModel.FarmPlot>())
        XCTAssertEqual(plots.count, 1)
        XCTAssertEqual(plots.first?.kind, .commonField)
    }

    @MainActor
    func test_farm_bootstrapRemovesOrphanedAndDuplicatePlots() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)   // seeds one common field

        // Simulate the old harvest bug: an orphaned user plot (no goal) reset
        // to .empty, plus a stray duplicate common field.
        context.insert(DBModel.FarmPlot(
            gridX: 5, kind: .crop, health: 100, state: .empty, goal: nil
        ))
        context.insert(DBModel.FarmPlot(
            gridX: 0, kind: .commonField, health: 100, state: .mature,
            createdAt: Date().addingTimeInterval(60)
        ))
        try context.save()

        var plots = try context.fetch(FetchDescriptor<DBModel.FarmPlot>())
        XCTAssertEqual(plots.count, 3, "precondition: orphan + duplicate present")

        // Re-bootstrap should reconcile away both bad rows.
        farm.bootstrap(in: context)

        plots = try context.fetch(FetchDescriptor<DBModel.FarmPlot>())
        XCTAssertEqual(plots.count, 1, "orphan and duplicate removed")
        XCTAssertEqual(plots.first?.kind, .commonField, "the surviving plot is the common field")
    }

    @MainActor
    func test_farm_bindPlot_allocatesAndCapacityCaps() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        let goals = RealGoalsInteractor(farm: farm)
        farm.bootstrap(in: context)

        // Default plotCapacity is 3 — first three add() calls succeed.
        for index in 0..<3 {
            goals.add(GoalDraft(title: "Goal \(index)", farmElementType: .animal), in: context)
        }
        try context.save()

        let allGoals = try context.fetch(FetchDescriptor<DBModel.Goal>())
        XCTAssertEqual(allGoals.count, 3)
        XCTAssertTrue(allGoals.allSatisfy { $0.plot != nil }, "all goals bound to a plot")

        // The 4th add() saves the goal but silently fails to bind a plot.
        goals.add(GoalDraft(title: "Overflow", farmElementType: .tree), in: context)
        try context.save()
        let after = try context.fetch(FetchDescriptor<DBModel.Goal>())
        let overflow = try XCTUnwrap(after.first { $0.title == "Overflow" })
        XCTAssertNil(overflow.plot, "over-capacity goal has no plot")

        // Bumping capacity then retrying succeeds.
        economy.credit(100, reason: "test", in: context)
        try farm.purchaseCapacity(in: context)
        try farm.bindPlot(to: overflow, in: context)
        XCTAssertNotNil(overflow.plot)
        XCTAssertEqual(overflow.plot?.kind, .tree)
    }

    @MainActor
    func test_farm_habitCompletionContributesToBoundPlot() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        let goals = RealGoalsInteractor(farm: farm)
        let habits = RealHabitsInteractor(scheduler: StubNotificationScheduler(), farm: farm)
        farm.bootstrap(in: context)

        goals.add(GoalDraft(title: "Read", farmElementType: .crop), in: context)
        habits.add(HabitDraft(title: "Read 10 pages"), in: context)
        try context.save()

        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Goal>()).first)
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)
        goals.setLinks(goal, tasks: [], habits: [habit], in: context)
        try context.save()

        let initialHealth = try XCTUnwrap(goal.plot?.health)
        habits.toggleDone(habit, on: Date(), in: context)
        try context.save()

        let after = try XCTUnwrap(goal.plot?.health)
        XCTAssertEqual(after, min(100, initialHealth + FarmTuning.habitContribution))
    }

    @MainActor
    func test_farm_backfillingPastDayDoesNotContributeToPlot() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        let goals = RealGoalsInteractor(farm: farm)
        let habits = RealHabitsInteractor(scheduler: StubNotificationScheduler(), farm: farm)
        farm.bootstrap(in: context)

        goals.add(GoalDraft(title: "Read", farmElementType: .crop), in: context)
        habits.add(HabitDraft(title: "Read 10 pages"), in: context)
        try context.save()

        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Goal>()).first)
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)
        goals.setLinks(goal, tasks: [], habits: [habit], in: context)
        try context.save()

        let initialHealth = try XCTUnwrap(goal.plot?.health)
        // Back-fill yesterday — the entry is recorded but no health is pumped.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        habits.toggleDone(habit, on: yesterday, in: context)
        try context.save()

        XCTAssertTrue(habit.isDone(on: yesterday), "back-filled entry is recorded")
        XCTAssertEqual(try XCTUnwrap(goal.plot?.health), initialHealth,
                       "back-filling a past day does not contribute health")
    }

    @MainActor
    func test_farm_unlinkedHabitFeedsCommonField() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        let habits = RealHabitsInteractor(scheduler: StubNotificationScheduler(), farm: farm)
        farm.bootstrap(in: context)

        habits.add(HabitDraft(title: "Stretch"), in: context)
        try context.save()
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)

        // Common field bootstraps at health=100 — knock it down so we can see a delta.
        let plots = try context.fetch(FetchDescriptor<DBModel.FarmPlot>())
        let common = try XCTUnwrap(plots.first { $0.kind == .commonField })
        common.health = 50

        habits.toggleDone(habit, on: Date(), in: context)
        try context.save()
        XCTAssertEqual(common.health, 50 + FarmTuning.commonFieldContribution)
    }

    @MainActor
    func test_farm_decayWithersThenKillsPlot() throws {
        let context = try makeFarmContext()
        let calendar = Calendar.current
        let farm = RealFarmInteractor(calendar: calendar)
        let goals = RealGoalsInteractor(farm: farm)
        farm.bootstrap(in: context)
        goals.add(GoalDraft(title: "Decay subject", farmElementType: .crop), in: context)
        try context.save()
        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Goal>()).first)
        let plot = try XCTUnwrap(goal.plot)

        // Force the lastDecayTick into the past so applyDailyDecay sees days elapsed.
        var fetchState = FetchDescriptor<DBModel.FarmState>()
        fetchState.fetchLimit = 1
        let state = try XCTUnwrap(try context.fetch(fetchState).first)
        let now = Date()
        // Seed decay tick; simulate 10 elapsed days to fully drain a plot at health=50 with 10/day decay.
        state.lastDecayTick = calendar.date(byAdding: .day, value: -10, to: now)
        plot.lastContribution = calendar.date(byAdding: .day, value: -10, to: now)
        try context.save()

        farm.applyDailyDecay(now: now, in: context)
        XCTAssertEqual(plot.health, 0)
        XCTAssertEqual(plot.state, .withered, "health 0 transitions to withered first")

        // Push lastContribution further back so the wither-to-dead window has elapsed,
        // then run another decay tick a day later.
        state.lastDecayTick = calendar.date(byAdding: .day, value: -1, to: now)
        plot.lastContribution = calendar.date(byAdding: .day, value: -10, to: now)
        farm.applyDailyDecay(now: now, in: context)
        XCTAssertEqual(plot.state, .dead, "withered too long becomes dead")
    }

    @MainActor
    func test_farm_pausedGoalPlotDoesNotDecay() throws {
        let context = try makeFarmContext()
        let calendar = Calendar.current
        let farm = RealFarmInteractor(calendar: calendar)
        let goals = RealGoalsInteractor(farm: farm)
        farm.bootstrap(in: context)
        goals.add(GoalDraft(title: "On hold", farmElementType: .crop), in: context)
        try context.save()
        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Goal>()).first)
        let plot = try XCTUnwrap(goal.plot)

        // Pause the goal, then run a multi-day decay tick.
        goals.setStatus(goal, status: .paused, in: context)
        var fetchState = FetchDescriptor<DBModel.FarmState>()
        fetchState.fetchLimit = 1
        let state = try XCTUnwrap(try context.fetch(fetchState).first)
        let now = Date()
        state.lastDecayTick = calendar.date(byAdding: .day, value: -5, to: now)
        let healthBefore = plot.health
        try context.save()

        farm.applyDailyDecay(now: now, in: context)
        XCTAssertEqual(plot.health, healthBefore, "paused goal's plot does not decay")
    }

    // MARK: - Quests

    @MainActor
    func test_quests_rollDailyIsIdempotent() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)
        let quests = RealQuestInteractor(rng: { 0 })

        let first = quests.rollDaily(on: Date(), in: context)
        try context.save()
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.map(\.slot), [0, 1, 2])

        let second = quests.rollDaily(on: Date(), in: context)
        XCTAssertEqual(second.map(\.id), first.map(\.id), "second call returns the same rows")
        let stored = try context.fetch(FetchDescriptor<DBModel.Quest>())
        XCTAssertEqual(stored.count, 3, "no duplicates created")
    }

    @MainActor
    func test_quests_rollDailyPullsFromOpenTasksAndHabits() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)
        let scheduler = StubNotificationScheduler()
        let tasks = RealTasksInteractor(scheduler: scheduler, farm: farm)
        let habits = RealHabitsInteractor(scheduler: scheduler, farm: farm)
        let quests = RealQuestInteractor(rng: { 0 })

        tasks.add(TaskDraft(title: "Pay bill", dueDate: Date(), priority: .high), in: context)
        habits.add(HabitDraft(title: "Stretch"), in: context)
        try context.save()

        let rolled = quests.rollDaily(on: Date(), in: context)
        XCTAssertEqual(rolled.count, 3)
        let kinds = Set(rolled.map(\.kind))
        XCTAssertTrue(kinds.contains(.taskDue), "uses available task")
        XCTAssertTrue(kinds.contains(.habitDue), "uses available habit")
        // Remaining slot pads with commonFieldTend.
        XCTAssertTrue(kinds.contains(.commonFieldTend))
    }

    @MainActor
    func test_quests_rerollCostsGoldAndBumpsCount() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        farm.bootstrap(in: context)
        // FarmState seeds with 100 starting gold; drain so this test can verify
        // the "no gold → throws" path before topping back up.
        try economy.spend(economy.balance(in: context), reason: "drain for test", in: context)
        let quests = RealQuestInteractor(economy: economy, rng: { 0 })

        let rolled = quests.rollDaily(on: Date(), in: context)
        let slot0 = rolled[0]

        // No gold → throws
        XCTAssertThrowsError(try quests.reroll(slot0, in: context)) { error in
            guard case QuestError.insufficientGold = error else {
                return XCTFail("expected insufficientGold, got \(error)")
            }
        }

        economy.credit(50, reason: "test", in: context)
        let balanceBefore = economy.balance(in: context)
        try quests.reroll(slot0, in: context)
        XCTAssertEqual(slot0.rerollCount, 1)
        XCTAssertEqual(economy.balance(in: context), balanceBefore - QuestTuning.rerollBaseCost)

        // Second re-roll on same slot costs base + step.
        try quests.reroll(slot0, in: context)
        XCTAssertEqual(slot0.rerollCount, 2)
        XCTAssertEqual(
            economy.balance(in: context),
            balanceBefore - QuestTuning.rerollBaseCost - (QuestTuning.rerollBaseCost + QuestTuning.rerollCostStep)
        )
    }

    @MainActor
    func test_quests_taskCompletionAutoClaims() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        farm.bootstrap(in: context)
        let quests = RealQuestInteractor(economy: economy, rng: { 0 })
        let tasks = RealTasksInteractor(scheduler: StubNotificationScheduler(), farm: farm, quests: quests)

        tasks.add(TaskDraft(title: "Pay bill", dueDate: Date(), priority: .normal), in: context)
        try context.save()
        let task = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Task>()).first)

        let rolled = quests.rollDaily(on: Date(), in: context)
        let taskQuest = try XCTUnwrap(rolled.first { $0.kind == .taskDue && $0.referenceID == task.id })
        XCTAssertEqual(taskQuest.state, .active)

        let goldBefore = economy.balance(in: context)
        tasks.toggleDone(task, in: context)
        try context.save()

        XCTAssertEqual(taskQuest.state, .completed, "completion auto-claims the quest")
        let commonFieldReward = rolled.first { $0.kind == .commonFieldTend }?.goldReward ?? 0
        XCTAssertEqual(economy.balance(in: context), goldBefore + taskQuest.goldReward + commonFieldReward)
    }

    @MainActor
    func test_quests_expireOldQuests() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)
        let quests = RealQuestInteractor(rng: { 0 })

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let stale = DBModel.Quest(
            day: Calendar.current.startOfDay(for: yesterday),
            slot: 0,
            kind: .commonFieldTend,
            goldReward: 3,
            state: .active
        )
        context.insert(stale)
        try context.save()

        quests.expireOldQuests(on: Date(), in: context)
        XCTAssertEqual(stale.state, .expired)
    }

    func test_notifications_staleHabitReminderIdentifiers() {
        let keepID = UUID()
        let valid: Set<String> = ["habit-reminder-\(keepID.uuidString)"]
        let pending = [
            "habit-reminder-\(keepID.uuidString)",          // current, keep
            "habit-reminder-\(UUID().uuidString)",          // orphan (deleted/archived)
            "habit-\(UUID().uuidString)",                   // legacy scheme
            "task-due-\(UUID().uuidString)",                // unrelated, keep
            "plot-alert-\(UUID().uuidString)"               // unrelated, keep
        ]
        let stale = RealNotificationScheduler.staleHabitReminderIdentifiers(pending: pending, valid: valid)
        XCTAssertEqual(Set(stale), Set([pending[1], pending[2]]))
    }

    @MainActor
    func test_quests_weeklyQuestNotExpiredMidWeek() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)
        let quests = RealQuestInteractor(rng: { 0 })

        let cal = Calendar.current
        // Roll the weekly quest at the start of this ISO week.
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let weekStart = cal.date(from: comps)!
        let weekly = try XCTUnwrap(quests.rollWeekly(on: weekStart, in: context))

        // Two days later, still within the same week — must remain active.
        let midWeek = cal.date(byAdding: .day, value: 2, to: weekStart)!
        quests.expireOldQuests(on: midWeek, in: context)
        XCTAssertEqual(weekly.state, .active)

        // Next week — now it should expire.
        let nextWeek = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart)!
        quests.expireOldQuests(on: nextWeek, in: context)
        XCTAssertEqual(weekly.state, .expired)
    }

    @MainActor
    func test_farm_replantRequiresDeadPlotAndCostsGold() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        let goals = RealGoalsInteractor(farm: farm)
        farm.bootstrap(in: context)
        // FarmState seeds with 100 starting gold; drain so the "no gold" branch
        // is reachable and the post-replant balance assertion stays at 0.
        try economy.spend(economy.balance(in: context), reason: "drain for test", in: context)
        goals.add(GoalDraft(title: "Subject", farmElementType: .crop), in: context)
        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Goal>()).first)
        let plot = try XCTUnwrap(goal.plot)

        XCTAssertThrowsError(try farm.replant(plot, in: context)) { error in
            XCTAssertTrue(error is FarmError)
        }

        // Force the plot dead, then replant.
        plot.state = .dead
        XCTAssertThrowsError(try farm.replant(plot, in: context), "no gold yet")
        economy.credit(FarmTuning.replantCost, reason: "test", in: context)
        try farm.replant(plot, in: context)
        XCTAssertEqual(plot.state, .growing)
        XCTAssertEqual(plot.health, FarmTuning.initialHealth)
        XCTAssertEqual(economy.balance(in: context), 0)
    }

    // MARK: - Streaks

    @MainActor
    func test_habit_streakIncrements() throws {
        let container = try ModelContainer(
            for: DBModel.Habit.self, DBModel.HabitLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let interactor = RealHabitsInteractor(scheduler: StubNotificationScheduler())

        interactor.add(HabitDraft(title: "Run"), in: context)
        try context.save()
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!

        interactor.toggleDone(habit, on: twoDaysAgo, in: context)
        interactor.toggleDone(habit, on: yesterday, in: context)
        interactor.toggleDone(habit, on: today, in: context)
        try context.save()

        XCTAssertEqual(habit.currentStreak, 3)
        XCTAssertEqual(habit.longestStreak, 3)
    }

    @MainActor
    func test_habit_weekdaysStreakSkipsWeekend() throws {
        let container = try ModelContainer(
            for: DBModel.Habit.self, DBModel.HabitLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let interactor = RealHabitsInteractor(scheduler: StubNotificationScheduler())

        interactor.add(HabitDraft(title: "Standup", frequency: .weekdays), in: context)
        try context.save()
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)

        let cal = Calendar.current
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d))!
        }
        // 2026-06-04 Thu, 06-05 Fri, 06-08 Mon (06-06/07 are the weekend).
        let thu = date(2026, 6, 4)
        let fri = date(2026, 6, 5)
        let mon = date(2026, 6, 8)
        XCTAssertTrue(cal.isDateInWeekend(date(2026, 6, 6)), "precondition: 06-06 is Saturday")

        interactor.toggleDone(habit, on: thu, in: context)
        interactor.toggleDone(habit, on: fri, in: context)
        interactor.toggleDone(habit, on: mon, in: context)
        try context.save()

        XCTAssertEqual(habit.currentStreak, 3, "Thu→Fri→Mon is an unbroken weekday streak")
        XCTAssertEqual(habit.longestStreak, 3)
    }

    @MainActor
    func test_habit_wasMissed_backfillCandidates() throws {
        let container = try ModelContainer(
            for: DBModel.Habit.self, DBModel.HabitLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let cal = Calendar.current

        // Pick a known weekday (Wednesday) so the weekdays-cadence assertions
        // don't depend on when the test runs.
        let wed = cal.date(from: DateComponents(year: 2026, month: 6, day: 3))!
        XCTAssertFalse(cal.isDateInWeekend(wed), "precondition: 2026-06-03 is a weekday")
        let sun = cal.date(from: DateComponents(year: 2026, month: 6, day: 7))!
        XCTAssertTrue(cal.isDateInWeekend(sun), "precondition: 2026-06-07 is a weekend")

        let daily = DBModel.Habit(title: "Floss", frequency: .daily)
        context.insert(daily)
        XCTAssertTrue(daily.wasMissed(on: wed, calendar: cal), "unlogged daily habit was missed")

        // Logging it for that day clears the candidate.
        context.insert(DBModel.HabitLogEntry(date: cal.startOfDay(for: wed), habit: daily))
        XCTAssertFalse(daily.wasMissed(on: wed, calendar: cal), "logged habit is not a candidate")

        // Weekdays habit isn't a candidate on a weekend (not due then).
        let weekdays = DBModel.Habit(title: "Standup", frequency: .weekdays)
        context.insert(weekdays)
        XCTAssertTrue(weekdays.wasMissed(on: wed, calendar: cal), "missed on a weekday")
        XCTAssertFalse(weekdays.wasMissed(on: sun, calendar: cal), "not due on a weekend")

        // Archived habits are never candidates.
        let archived = DBModel.Habit(title: "Old", frequency: .daily, archived: true)
        context.insert(archived)
        XCTAssertFalse(archived.wasMissed(on: wed, calendar: cal))
    }

    @MainActor
    func test_habit_mostRecentMissedDay_weekdaysSkipWeekend() throws {
        let container = try ModelContainer(
            for: DBModel.Habit.self, DBModel.HabitLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let cal = Calendar.current

        // 2026-06-08 is a Monday; the previous scheduled weekday is Fri 06-05.
        let monday = cal.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        let friday = cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 6, day: 5))!)
        XCTAssertFalse(cal.isDateInWeekend(monday))

        // A weekdays habit opened Monday surfaces its missed Friday, not Sunday.
        let weekdays = DBModel.Habit(title: "Standup", frequency: .weekdays)
        context.insert(weekdays)
        XCTAssertEqual(
            weekdays.mostRecentMissedDay(before: monday, calendar: cal).map { cal.startOfDay(for: $0) },
            friday,
            "weekdays habit looks back past the weekend to Friday")

        // Logging Friday clears the candidate.
        context.insert(DBModel.HabitLogEntry(date: friday, habit: weekdays))
        XCTAssertNil(weekdays.mostRecentMissedDay(before: monday, calendar: cal))

        // A daily habit's most recent missed day is simply yesterday (Sunday).
        let sunday = cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 6, day: 7))!)
        let daily = DBModel.Habit(title: "Floss", frequency: .daily)
        context.insert(daily)
        XCTAssertEqual(
            daily.mostRecentMissedDay(before: monday, calendar: cal).map { cal.startOfDay(for: $0) },
            sunday,
            "daily habit's most recent missed day is yesterday")
    }

    @MainActor
    func test_habit_untoggleTodayDecreasesStreakByOne() throws {
        let container = try ModelContainer(
            for: DBModel.Habit.self, DBModel.HabitLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let interactor = RealHabitsInteractor(scheduler: StubNotificationScheduler())

        interactor.add(HabitDraft(title: "Floss"), in: context)
        try context.save()
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Build a 5-day streak ending today.
        for back in stride(from: 4, through: 0, by: -1) {
            interactor.toggleDone(habit, on: cal.date(byAdding: .day, value: -back, to: today)!, in: context)
        }
        try context.save()
        XCTAssertEqual(habit.currentStreak, 5)

        // Un-log today — the streak should drop to 4 (the run ending yesterday),
        // not collapse to 0.
        interactor.toggleDone(habit, on: today, in: context)
        try context.save()
        XCTAssertEqual(habit.currentStreak, 4, "un-logging today decreases the streak by one")
    }

    @MainActor
    func test_habit_streakGapPreventsChaining() throws {
        let container = try ModelContainer(
            for: DBModel.Habit.self, DBModel.HabitLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let interactor = RealHabitsInteractor(scheduler: StubNotificationScheduler())

        interactor.add(HabitDraft(title: "Read"), in: context)
        try context.save()
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: today)!

        // Logged three days ago — streak at that point = 1.
        interactor.toggleDone(habit, on: threeDaysAgo, in: context)
        try context.save()
        XCTAssertEqual(habit.currentStreak, 1, "streak is 1 for the isolated logged day")
        XCTAssertEqual(habit.longestStreak, 1)

        // Log today — gap means today starts a new chain of 1, not 4.
        interactor.toggleDone(habit, on: today, in: context)
        try context.save()
        XCTAssertEqual(habit.currentStreak, 1, "gap prevents chaining: today-only streak")
        XCTAssertEqual(habit.longestStreak, 1)
    }

    @MainActor
    func test_habit_streakMilestoneCreditsGold() throws {
        let container = try ModelContainer(
            for: DBModel.Habit.self, DBModel.HabitLogEntry.self,
                DBModel.FarmState.self, DBModel.FarmPlot.self, DBModel.Goal.self,
                DBModel.Task.self, DBModel.HabitLogEntry.self, DBModel.Quest.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        farm.bootstrap(in: context)
        let startingGold = economy.balance(in: context)

        let interactor = RealHabitsInteractor(
            scheduler: StubNotificationScheduler(),
            economy: economy,
            farm: StubFarmInteractor()
        )
        interactor.add(HabitDraft(title: "Meditate"), in: context)
        try context.save()
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)

        // Simulate 7 consecutive days ending today.
        let cal = Calendar.current
        for daysAgo in stride(from: 6, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
            interactor.toggleDone(habit, on: day, in: context)
        }
        try context.save()

        XCTAssertEqual(habit.currentStreak, 7)
        XCTAssertEqual(habit.lastStreakMilestone, 7)
        XCTAssertEqual(
            economy.balance(in: context),
            startingGold + StreakTuning.bonus(at: 7),
            "7-day milestone credited"
        )
    }

    @MainActor
    func test_habit_streakMilestoneNotAwardedTwice() throws {
        let container = try ModelContainer(
            for: DBModel.Habit.self, DBModel.HabitLogEntry.self,
                DBModel.FarmState.self, DBModel.FarmPlot.self, DBModel.Goal.self,
                DBModel.Task.self, DBModel.Quest.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        farm.bootstrap(in: context)

        let interactor = RealHabitsInteractor(
            scheduler: StubNotificationScheduler(),
            economy: economy,
            farm: StubFarmInteractor()
        )
        interactor.add(HabitDraft(title: "Walk"), in: context)
        try context.save()
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)

        let cal = Calendar.current
        // Build 7-day streak ending yesterday.
        for daysAgo in stride(from: 7, through: 1, by: -1) {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
            interactor.toggleDone(habit, on: day, in: context)
        }
        try context.save()
        let goldAfterFirstMilestone = economy.balance(in: context)

        // Toggle today: streak becomes 8, no new milestone until 14.
        interactor.toggleDone(habit, on: Date(), in: context)
        try context.save()

        XCTAssertEqual(habit.currentStreak, 8)
        XCTAssertEqual(habit.lastStreakMilestone, 7, "milestone stays at 7 until 14-day")
        XCTAssertEqual(economy.balance(in: context), goldAfterFirstMilestone, "no double award")
    }

    // MARK: - harvestMature quest

    @MainActor
    func test_quests_harvestMatureRolledAndAutoClaims() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        let goals = RealGoalsInteractor(farm: farm)
        let quests = RealQuestInteractor(economy: economy, rng: { 0 })
        let habits = RealHabitsInteractor(
            scheduler: StubNotificationScheduler(), economy: economy,
            farm: farm, quests: quests)
        farm.bootstrap(in: context)

        // Two mature goal plots satisfy the threshold.
        goals.add(GoalDraft(title: "Run",  farmElementType: .crop), in: context)
        goals.add(GoalDraft(title: "Read", farmElementType: .crop), in: context)
        try context.save()
        for goal in try context.fetch(FetchDescriptor<DBModel.Goal>()) {
            goal.plot?.health = FarmTuning.matureThreshold + 10
            goal.plot?.state = .mature
        }
        try context.save()

        // rollDaily should include a harvestMature slot.
        let rolled = quests.rollDaily(on: Date(), in: context)
        let harvestQuest = try XCTUnwrap(
            rolled.first { $0.kind == .harvestMature },
            "harvestMature quest should be rolled when ≥2 living goal plots exist"
        )
        XCTAssertEqual(harvestQuest.state, .active)

        // Logging any habit triggers checkFarmQuests which should auto-claim.
        habits.add(HabitDraft(title: "Stretch"), in: context)
        try context.save()
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)
        let goldBefore = economy.balance(in: context)

        habits.toggleDone(habit, on: Date(), in: context)
        try context.save()

        XCTAssertEqual(harvestQuest.state, .completed, "harvestMature auto-claimed after checkFarmQuests")
        // The refresh-on-add upgrade slotted the new habit into a quest, so the
        // habitDue quest auto-claims here too. The remaining commonFieldTend slot
        // also auto-claims because the habit is unlinked. All rewards land.
        let commonFieldReward = rolled.filter { $0.kind == .commonFieldTend }.reduce(0) { $0 + $1.goldReward }
        XCTAssertEqual(
            economy.balance(in: context),
            goldBefore + harvestQuest.goldReward + QuestTuning.habitReward + commonFieldReward
        )
    }

    // MARK: - Weekly harvest quest

    @MainActor
    func test_weeklyQuest_rollsOnce() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let quests = RealQuestInteractor(economy: economy)

        let q1 = quests.rollWeekly(on: Date(), in: context)
        let q2 = quests.rollWeekly(on: Date(), in: context)
        try context.save()

        XCTAssertNotNil(q1, "weekly quest created on first roll")
        XCTAssertEqual(q1?.id, q2?.id, "second call returns same quest — idempotent")
        let all = try context.fetch(FetchDescriptor<DBModel.Quest>(
            predicate: #Predicate { $0.slot == 3 }
        ))
        XCTAssertEqual(all.count, 1, "only one weekly quest slot per week")
    }

    @MainActor
    func test_weeklyQuest_tracksProgress() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let quests = RealQuestInteractor(economy: economy)

        let quest = try XCTUnwrap(quests.rollWeekly(on: Date(), in: context))
        try context.save()
        XCTAssertEqual(quest.progress, 0)

        quests.trackMatureTransitions(count: 3, in: context)
        try context.save()

        XCTAssertEqual(quest.progress, 3, "progress incremented by 3")
        XCTAssertEqual(quest.state, .active, "not yet claimed — target is \(quest.progressTarget)")
    }

    @MainActor
    func test_weeklyQuest_autoClaimsAtTarget() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        let quests = RealQuestInteractor(economy: economy)
        farm.bootstrap(in: context)

        let weekQuest = try XCTUnwrap(quests.rollWeekly(on: Date(), in: context))
        let target = weekQuest.progressTarget
        let goldBefore = economy.balance(in: context)
        try context.save()

        // Increment to one below target — quest still active.
        quests.trackMatureTransitions(count: target - 1, in: context)
        try context.save()
        XCTAssertEqual(weekQuest.progress, target - 1)
        XCTAssertEqual(weekQuest.state, .active, "not yet claimed")

        // Final transition reaches target — auto-claim fires.
        quests.trackMatureTransitions(count: 1, in: context)
        try context.save()

        XCTAssertEqual(weekQuest.state, .completed, "weekly quest auto-claimed at target")
        XCTAssertEqual(
            economy.balance(in: context),
            goldBefore + weekQuest.goldReward,
            "weekly reward credited"
        )
    }

    // MARK: - Goal metrics

    @MainActor
    func test_metric_logProgressIncrementsValueAndPumpsHealth() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)
        let goals = RealGoalsInteractor(farm: farm)

        goals.add(
            GoalDraft(title: "Marathon", metricUnit: "miles", metricTarget: 26.2),
            in: context
        )
        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Goal>()).first)
        let plot = try XCTUnwrap(goal.plot)
        let healthBefore = plot.health

        goals.logMetricProgress(goal, amount: 5.0, in: context)
        goals.logMetricProgress(goal, amount: 3.5, in: context)

        XCTAssertEqual(goal.metricValue, 8.5, accuracy: 0.0001)
        XCTAssertGreaterThan(plot.health, healthBefore, "Plot health pumped by metric log")
        XCTAssertEqual(goal.metricProgress, 8.5 / 26.2, accuracy: 0.0001)
    }

    @MainActor
    func test_metric_logIgnoredWhenNoUnit() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)
        let goals = RealGoalsInteractor(farm: farm)

        // No metric unit configured → logMetricProgress should be a no-op.
        goals.add(GoalDraft(title: "No metric"), in: context)
        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Goal>()).first)

        goals.logMetricProgress(goal, amount: 100, in: context)

        XCTAssertEqual(goal.metricValue, 0)
        XCTAssertFalse(goal.hasMetric)
    }

    // MARK: - refreshTodaysCommonFieldSlots (bug: fresh installs show only commonField)

    @MainActor
    func test_refresh_upgradesCommonFieldToNewHabit() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        farm.bootstrap(in: context)
        let quests = RealQuestInteractor(economy: economy)
        let habits = RealHabitsInteractor(
            scheduler: StubNotificationScheduler(), economy: economy,
            farm: farm, quests: quests)

        // No tasks/habits yet → rollDaily fills all 3 slots with commonField.
        let initial = quests.rollDaily(on: Date(), in: context)
        try context.save()
        XCTAssertEqual(initial.filter { $0.kind == .commonFieldTend }.count, 3)

        // User adds a habit. The add path should upgrade a placeholder slot.
        habits.add(HabitDraft(title: "Stretch"), in: context)
        try context.save()

        let after = quests.rollDaily(on: Date(), in: context)
        let habitSlot = after.first { $0.kind == .habitDue }
        XCTAssertNotNil(habitSlot, "habit should be assigned to a quest slot after add")
        XCTAssertEqual(after.filter { $0.kind == .commonFieldTend }.count, 2)
    }

    @MainActor
    func test_refresh_upgradesCommonFieldToNewTask() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        farm.bootstrap(in: context)
        let quests = RealQuestInteractor(economy: economy)
        let tasks = RealTasksInteractor(
            scheduler: StubNotificationScheduler(), farm: farm, quests: quests)

        let initial = quests.rollDaily(on: Date(), in: context)
        try context.save()
        XCTAssertEqual(initial.filter { $0.kind == .commonFieldTend }.count, 3)

        // Task with a dueDate <= end-of-today is eligible for today's pool.
        tasks.add(TaskDraft(title: "Pay bill", dueDate: Date()), in: context)
        try context.save()

        let after = quests.rollDaily(on: Date(), in: context)
        XCTAssertNotNil(after.first { $0.kind == .taskDue }, "task quest should appear")
        XCTAssertEqual(after.filter { $0.kind == .commonFieldTend }.count, 2)
    }

    @MainActor
    func test_refresh_isNoOpWhenNoCandidates() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        farm.bootstrap(in: context)
        let quests = RealQuestInteractor(economy: economy)

        quests.rollDaily(on: Date(), in: context)
        try context.save()
        let beforeIDs = try context.fetch(FetchDescriptor<DBModel.Quest>()).map(\.id).sorted()

        // No tasks/habits exist → refresh has nothing to do.
        quests.refreshTodaysCommonFieldSlots(in: context)
        try context.save()

        let after = try context.fetch(FetchDescriptor<DBModel.Quest>())
        XCTAssertEqual(after.map(\.id).sorted(), beforeIDs)
        XCTAssertTrue(after.allSatisfy { $0.kind == .commonFieldTend })
    }

    // MARK: - Weekly cadence

    @MainActor
    func test_weeklyHabit_targetMetMarksWeekComplete() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        farm.bootstrap(in: context)
        let habits = RealHabitsInteractor(
            scheduler: StubNotificationScheduler(), economy: economy, farm: farm)

        habits.add(HabitDraft(title: "Gym", frequency: .weekly, weeklyTarget: 3), in: context)
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)

        let cal = Calendar.current
        // Find the start of this week so all log days fall in the same ISO week.
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let weekStart = try XCTUnwrap(cal.date(from: comps))

        XCTAssertFalse(habit.isWeekComplete(containing: weekStart))
        habits.toggleDone(habit, on: weekStart, in: context)
        habits.toggleDone(habit, on: cal.date(byAdding: .day, value: 1, to: weekStart)!, in: context)
        XCTAssertFalse(habit.isWeekComplete(containing: weekStart), "2/3 — not complete yet")
        habits.toggleDone(habit, on: cal.date(byAdding: .day, value: 2, to: weekStart)!, in: context)
        XCTAssertTrue(habit.isWeekComplete(containing: weekStart), "3/3 — week complete")
    }

    @MainActor
    func test_weeklyHabit_streakCountsConsecutiveCompletedWeeks() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        farm.bootstrap(in: context)
        let habits = RealHabitsInteractor(
            scheduler: StubNotificationScheduler(), economy: economy, farm: farm)

        habits.add(HabitDraft(title: "Yoga", frequency: .weekly, weeklyTarget: 2), in: context)
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)

        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let thisWeek = try XCTUnwrap(cal.date(from: comps))

        // Log 2 entries in each of the last 3 ISO weeks (current included).
        for weeksAgo in 0...2 {
            let weekStart = cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek)!
            habits.toggleDone(habit, on: weekStart, in: context)
            habits.toggleDone(habit, on: cal.date(byAdding: .day, value: 2, to: weekStart)!, in: context)
        }
        // Skip one week — streak chain breaks at that gap.
        // Two more complete weeks before the gap should NOT count.
        let gapWeek = cal.date(byAdding: .weekOfYear, value: -3, to: thisWeek)!
        // intentionally only log 1 entry in gapWeek — below target
        habits.toggleDone(habit, on: gapWeek, in: context)

        XCTAssertEqual(habit.currentStreak, 3, "3 consecutive completed weeks ending now")
    }

    @MainActor
    func test_weeklyHabit_questPoolExcludesWhenTargetMet() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        farm.bootstrap(in: context)
        let quests = RealQuestInteractor(economy: economy)
        let habits = RealHabitsInteractor(
            scheduler: StubNotificationScheduler(), economy: economy,
            farm: farm, quests: quests)

        habits.add(HabitDraft(title: "Run", frequency: .weekly, weeklyTarget: 2), in: context)
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)

        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let weekStart = try XCTUnwrap(cal.date(from: comps))
        // Log two entries on Monday and Tuesday of this week — always in-week
        // regardless of which day the test runs. The habit is excluded from the
        // quest pool because isWeekComplete returns true (2 entries ≥ target 2).
        habits.toggleDone(habit, on: weekStart, in: context)
        habits.toggleDone(habit, on: cal.date(byAdding: .day, value: 1, to: weekStart)!, in: context)

        // Roll today's quests — weekly habit with target already met must NOT be picked.
        let rolled = quests.rollDaily(on: Date(), in: context)
        let pickedHabit = rolled.first { $0.referenceID == habit.id }
        XCTAssertNil(pickedHabit, "weekly habit excluded from quest pool once target is met")
    }

    // MARK: - Persistence (regression: data must survive a context reload)

    @MainActor
    func test_addedGoalSurvivesContextReload() throws {
        let container = try ModelContainer.appModelContainer(inMemoryOnly: true)
        let context = ModelContext(container)
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)
        let goals = RealGoalsInteractor(farm: farm)

        goals.add(GoalDraft(title: "Run a marathon"), in: context)

        // Drop the context — a fresh one reads from the underlying store.
        // If `add` doesn't save, the new context sees no goal.
        let fresh = ModelContext(container)
        let found = try fresh.fetch(FetchDescriptor<DBModel.Goal>())
        XCTAssertEqual(found.count, 1, "goal must persist immediately, not rely on autosave")
        XCTAssertEqual(found.first?.title, "Run a marathon")
    }

    @MainActor
    func test_addedHabitSurvivesContextReload() throws {
        let container = try ModelContainer.appModelContainer(inMemoryOnly: true)
        let context = ModelContext(container)
        let habits = RealHabitsInteractor(scheduler: StubNotificationScheduler())

        habits.add(HabitDraft(title: "Stretch"), in: context)

        let fresh = ModelContext(container)
        let found = try fresh.fetch(FetchDescriptor<DBModel.Habit>())
        XCTAssertEqual(found.count, 1, "habit must persist immediately, not rely on autosave")
        XCTAssertEqual(found.first?.title, "Stretch")
    }

    // MARK: - archiveAndDelete (existing test, just moved after new tests)

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

    // MARK: - Recurring tasks

    func test_recurrence_nextDate_daily() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let monday = cal.date(from: DateComponents(year: 2025, month: 1, day: 6))! // Monday
        let next = TaskRecurrence.daily.nextDate(after: monday, calendar: cal)
        let comps = cal.dateComponents([.year, .month, .day, .weekday], from: next)
        XCTAssertEqual(comps.day, 7)    // Tuesday
        XCTAssertEqual(comps.weekday, 3)
    }

    func test_recurrence_nextDate_weekdays_skipsWeekend() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let friday = cal.date(from: DateComponents(year: 2025, month: 1, day: 10))! // Friday
        let next = TaskRecurrence.weekdays.nextDate(after: friday, calendar: cal)
        let comps = cal.dateComponents([.weekday], from: next)
        XCTAssertEqual(comps.weekday, 2) // Monday (skipped Sat+Sun)
    }

    func test_recurrence_nextDate_weekdays_fromWednesday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let wednesday = cal.date(from: DateComponents(year: 2025, month: 1, day: 8))!
        let next = TaskRecurrence.weekdays.nextDate(after: wednesday, calendar: cal)
        let comps = cal.dateComponents([.weekday], from: next)
        XCTAssertEqual(comps.weekday, 5) // Thursday
    }

    func test_recurrence_nextDate_weekly() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2025, month: 1, day: 6))!
        let next = TaskRecurrence.weekly.nextDate(after: date, calendar: cal)
        let comps = cal.dateComponents([.year, .month, .day], from: next)
        XCTAssertEqual(comps.day, 13)
        XCTAssertEqual(comps.month, 1)
    }

    func test_recurrence_nextDate_monthly() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2025, month: 1, day: 31))!
        let next = TaskRecurrence.monthly.nextDate(after: date, calendar: cal)
        let comps = cal.dateComponents([.month], from: next)
        XCTAssertEqual(comps.month, 2) // Feb — Calendar clips to Feb 28
    }

    @MainActor
    func test_recurringTask_toggleDone_spawnsNextOccurrence() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let context = try makeFarmContext()
        let interactor = RealTasksInteractor(calendar: cal)

        let due = cal.date(from: DateComponents(year: 2025, month: 3, day: 10))!
        interactor.add(
            TaskDraft(title: "Water plants", dueDate: due, recurrence: .daily),
            in: context
        )

        let task = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Task>()).first)
        interactor.toggleDone(task, in: context)

        let all = try context.fetch(FetchDescriptor<DBModel.Task>())
        XCTAssertEqual(all.count, 2)

        let original = try XCTUnwrap(all.first { $0.isDone })
        let spawned  = try XCTUnwrap(all.first { !$0.isDone })

        XCTAssertEqual(original.title, "Water plants")
        XCTAssertEqual(spawned.title, "Water plants")
        XCTAssertEqual(spawned.recurrence, .daily)

        let spawnedComps = cal.dateComponents([.year, .month, .day], from: spawned.dueDate!)
        XCTAssertEqual(spawnedComps.year,  2025)
        XCTAssertEqual(spawnedComps.month, 3)
        XCTAssertEqual(spawnedComps.day,   11)
    }

    @MainActor
    func test_recurringTask_weekly_correctNextDate() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let context = try makeFarmContext()
        let interactor = RealTasksInteractor(calendar: cal)

        let due = cal.date(from: DateComponents(year: 2025, month: 4, day: 1))! // Tuesday
        interactor.add(
            TaskDraft(title: "Weekly review", dueDate: due, recurrence: .weekly),
            in: context
        )

        let task = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Task>()).first)
        interactor.toggleDone(task, in: context)

        let spawned = try XCTUnwrap(
            try context.fetch(FetchDescriptor<DBModel.Task>()).first { !$0.isDone }
        )
        let comps = cal.dateComponents([.year, .month, .day], from: spawned.dueDate!)
        XCTAssertEqual(comps.day, 8)   // April 8
        XCTAssertEqual(comps.month, 4)
    }

    @MainActor
    func test_nonRecurringTask_toggleDone_noSpawn() throws {
        let context = try makeFarmContext()
        let interactor = RealTasksInteractor()

        interactor.add(TaskDraft(title: "One-off task"), in: context)
        let task = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Task>()).first)
        interactor.toggleDone(task, in: context)

        let all = try context.fetch(FetchDescriptor<DBModel.Task>())
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0].isDone)
    }

    // MARK: - Stats / Insights

    @MainActor
    func test_stats_entryCountMatchesLoggedHabits() throws {
        let context = try makeFarmContext()
        let habitInteractor = RealHabitsInteractor()

        // Insert two habits and log them
        habitInteractor.add(HabitDraft(title: "Run"), in: context)
        habitInteractor.add(HabitDraft(title: "Read"), in: context)
        let habits = try context.fetch(FetchDescriptor<DBModel.Habit>())
        XCTAssertEqual(habits.count, 2)

        for habit in habits {
            habitInteractor.toggleDone(habit, on: Date(), in: context)
        }

        let entries = try context.fetch(FetchDescriptor<DBModel.HabitLogEntry>())
        XCTAssertEqual(entries.count, 2)
    }

    @MainActor
    func test_stats_goalContributionCounting() throws {
        let context = try makeFarmContext()
        let habitInteractor = RealHabitsInteractor()
        let goalInteractor  = RealGoalsInteractor(farm: StubFarmInteractor())
        let taskInteractor  = RealTasksInteractor()

        // Create a goal and link a habit to it
        goalInteractor.add(GoalDraft(title: "Fitness"), in: context)
        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Goal>()).first)

        habitInteractor.add(HabitDraft(title: "Run"), in: context)
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)
        goal.linkedHabits = [habit]

        // Log the habit twice
        habitInteractor.toggleDone(habit, on: Date(), in: context)
        habitInteractor.toggleDone(
            habit,
            on: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
            in: context
        )

        // Link a completed task
        taskInteractor.add(TaskDraft(title: "Gym session"), in: context)
        let task = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Task>()).first)
        goal.linkedTasks = [task]
        taskInteractor.toggleDone(task, in: context)
        context.saveQuietly()

        // Verify contributions: 2 habit entries + 1 completed task = 3
        let habitContribs = (goal.linkedHabits ?? []).reduce(0) { $0 + ($1.entries?.count ?? 0) }
        let taskContribs  = (goal.linkedTasks ?? []).filter { $0.isDone }.count
        XCTAssertEqual(habitContribs + taskContribs, 3)
    }

    @MainActor
    func test_stats_questKindGrouping() throws {
        let context = try makeFarmContext()

        // Insert completed quests of different kinds
        let q1 = DBModel.Quest(kind: .taskDue,    goldReward: 10, state: .completed)
        let q2 = DBModel.Quest(kind: .taskDue,    goldReward: 10, state: .completed)
        let q3 = DBModel.Quest(kind: .habitDue,   goldReward: 10, state: .completed)
        let q4 = DBModel.Quest(kind: .habitDue,   goldReward: 10, state: .active)
        context.insert(q1); context.insert(q2); context.insert(q3); context.insert(q4)
        context.saveQuietly()

        let all = try context.fetch(FetchDescriptor<DBModel.Quest>())
        let completed = all.filter { $0.state == .completed }
        XCTAssertEqual(completed.count, 3)

        let grouped = Dictionary(grouping: completed) { $0.kind }
        XCTAssertEqual(grouped[.taskDue]?.count, 2)
        XCTAssertEqual(grouped[.habitDue]?.count, 1)
        XCTAssertNil(grouped[.commonFieldTend])
    }

    // MARK: - Weather

    @MainActor
    func test_weather_rollDaily_isIdempotent() throws {
        let context = try makeFarmContext()
        let interactor = RealWeatherInteractor(
            economy: StubEconomyInteractor(),
            farm: StubFarmInteractor()
        )
        let today = Date()
        interactor.rollDaily(on: today, in: context)
        interactor.rollDaily(on: today, in: context)  // second roll should no-op

        let all = try context.fetch(FetchDescriptor<DBModel.WeatherEvent>())
        XCTAssertEqual(all.count, 1)
    }

    @MainActor
    func test_weather_rollDaily_differentDaysProduceTwoEvents() throws {
        let context = try makeFarmContext()
        let interactor = RealWeatherInteractor(
            economy: StubEconomyInteractor(),
            farm: StubFarmInteractor()
        )
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        interactor.rollDaily(on: yesterday, in: context)
        interactor.rollDaily(on: today, in: context)

        let all = try context.fetch(FetchDescriptor<DBModel.WeatherEvent>())
        XCTAssertEqual(all.count, 2)
    }

    @MainActor
    func test_weather_rainDoublesHabitContribution() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)

        // Insert a rain event covering now
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let rain = DBModel.WeatherEvent(kind: .rain, startedAt: today, expiresAt: tomorrow)
        context.insert(rain)
        context.saveQuietly()

        // Add a goal+plot and link a habit
        let goalInteractor = RealGoalsInteractor(farm: farm)
        goalInteractor.add(GoalDraft(title: "Fitness"), in: context)
        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Goal>()).first)

        let habitInteractor = RealHabitsInteractor(farm: farm)
        habitInteractor.add(HabitDraft(title: "Run"), in: context)
        let habit = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Habit>()).first)
        goal.linkedHabits = [habit]
        habit.goals = [goal]
        context.saveQuietly()

        let plot = try XCTUnwrap(goal.plot)
        let healthBefore = plot.health

        habitInteractor.toggleDone(habit, on: Date(), in: context)

        // Rain doubles the 20-pt habit contribution → expect 40 pts gained
        XCTAssertEqual(plot.health, min(100, healthBefore + FarmTuning.habitContribution * 2))
    }

    @MainActor
    func test_weather_droughtHalvesTaskContribution() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)

        // Insert a drought event
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let drought = DBModel.WeatherEvent(kind: .drought, startedAt: today, expiresAt: tomorrow)
        context.insert(drought)
        context.saveQuietly()

        let goalInteractor = RealGoalsInteractor(farm: farm)
        goalInteractor.add(GoalDraft(title: "Career"), in: context)
        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Goal>()).first)

        let taskInteractor = RealTasksInteractor(farm: farm)
        taskInteractor.add(TaskDraft(title: "Write report", priority: .normal), in: context)
        let task = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Task>()).first)
        goal.linkedTasks = [task]
        task.goals = [goal]
        context.saveQuietly()

        let plot = try XCTUnwrap(goal.plot)
        let healthBefore = plot.health

        taskInteractor.toggleDone(task, in: context)

        // Drought halves normal-priority task contribution (10 base + 5 bonus = 15 → 8 rounded)
        let baseAmount = FarmTuning.taskBaseContribution + (FarmTuning.taskPriorityBonus[.normal] ?? 0)
        let expected = max(1, Int((Double(baseAmount) * 0.5).rounded()))
        XCTAssertEqual(plot.health, min(100, healthBefore + expected))
    }

    // MARK: - Achievement tests

    @MainActor
    func test_achievement_firstHarvestUnlockedOnMature() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)
        let economy = RealEconomyInteractor()
        economy.credit(200, reason: "test-seed", in: context)

        let achievements = RealAchievementInteractor()

        // No achievements yet.
        let before = try context.fetch(FetchDescriptor<DBModel.Achievement>())
        XCTAssertTrue(before.isEmpty)

        // Manually set totalMatureTransitions to 1 and run checkAll.
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<DBModel.FarmState>()).first)
        state.totalMatureTransitions = 1
        achievements.checkAll(in: context)

        let after = try context.fetch(FetchDescriptor<DBModel.Achievement>())
        XCTAssertTrue(after.contains { $0.slug == "first_harvest" })
    }

    @MainActor
    func test_achievement_idempotent() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)

        let achievements = RealAchievementInteractor()

        let state = try XCTUnwrap(context.fetch(FetchDescriptor<DBModel.FarmState>()).first)
        state.totalMatureTransitions = 10

        // checkAll twice — still only one row per slug.
        achievements.checkAll(in: context)
        achievements.checkAll(in: context)

        let rows = try context.fetch(FetchDescriptor<DBModel.Achievement>())
        let harvestSlugs = rows.filter { $0.slug == "first_harvest" }
        XCTAssertEqual(harvestSlugs.count, 1, "Idempotent — no duplicate achievements")
    }

    @MainActor
    func test_achievement_goldEarnedTriggersPennyPincher() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)
        let economy = RealEconomyInteractor()

        // Credit exactly 500 gold — should trigger penny_pincher (totalGoldEarned tracks it).
        economy.credit(500, reason: "test", in: context)

        let achievements = RealAchievementInteractor()
        achievements.checkAll(in: context)

        let rows = try context.fetch(FetchDescriptor<DBModel.Achievement>())
        XCTAssertTrue(rows.contains { $0.slug == "penny_pincher" })
        XCTAssertFalse(rows.contains { $0.slug == "gold_rush" }, "5k threshold not met")
    }

    @MainActor
    func test_achievement_replantTriggersGreenThumb() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)
        let economy = RealEconomyInteractor()

        // Seed enough gold for the replant cost.
        economy.credit(200, reason: "test", in: context)

        // Bind a goal + plot, then kill it.
        let goalInteractor = RealGoalsInteractor(farm: farm)
        goalInteractor.add(GoalDraft(title: "Exercise"), in: context)
        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<DBModel.Goal>()).first)
        let plot = try XCTUnwrap(goal.plot)
        plot.state = .dead
        context.saveQuietly()

        let achievements = RealAchievementInteractor()
        let farmWithAchievements = RealFarmInteractor(achievements: achievements)

        try farmWithAchievements.replant(plot, in: context)

        let rows = try context.fetch(FetchDescriptor<DBModel.Achievement>())
        XCTAssertTrue(rows.contains { $0.slug == "green_thumb" })
        XCTAssertEqual(plot.state, .growing)
    }

    @MainActor
    func test_achievement_weekStrongUnlockedOnSevenDayStreak() throws {
        let context = try makeFarmContext()
        let farm = RealFarmInteractor()
        farm.bootstrap(in: context)

        let achievements = RealAchievementInteractor()

        // Insert a habit with currentStreak = 7.
        let habit = DBModel.Habit(title: "Meditate", frequency: .daily)
        context.insert(habit)
        habit.currentStreak = 7
        context.saveQuietly()

        achievements.checkAll(in: context)

        let rows = try context.fetch(FetchDescriptor<DBModel.Achievement>())
        XCTAssertTrue(rows.contains { $0.slug == "week_strong" })
        XCTAssertFalse(rows.contains { $0.slug == "month_strong" }, "30-day threshold not met")
    }

    // MARK: - Tool tests

    @MainActor
    func test_tool_purchase_debitsGoldAndPersists() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let tools = RealToolInteractor(economy: economy)
        let farm = RealFarmInteractor(economy: economy)

        // Bootstrap seeds 100g; credit 200 more → 300g total.
        farm.bootstrap(in: context)
        economy.credit(200, reason: "seed", in: context)

        let watering = ToolCatalog.all.first { $0.slug == "watering_can_ii" }!
        try tools.purchase(slug: watering.slug, in: context)

        let state = try context.fetch(FetchDescriptor<DBModel.FarmState>()).first!
        XCTAssertEqual(state.gold, 300 - watering.goldCost)   // 225g

        let owned = try context.fetch(FetchDescriptor<DBModel.OwnedTool>())
        XCTAssertEqual(owned.count, 1)
        XCTAssertEqual(owned.first?.slug, "watering_can_ii")
    }

    @MainActor
    func test_tool_idempotent_purchaseFails() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let tools = RealToolInteractor(economy: economy)
        let farm = RealFarmInteractor(economy: economy)

        farm.bootstrap(in: context)
        economy.credit(200, reason: "seed", in: context)

        let watering = ToolCatalog.all.first { $0.slug == "watering_can_ii" }!
        try tools.purchase(slug: watering.slug, in: context)
        XCTAssertThrowsError(try tools.purchase(slug: watering.slug, in: context))
    }

    @MainActor
    func test_tool_habitBonusIsAdditive() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let tools = RealToolInteractor(economy: economy)
        let farm = RealFarmInteractor(economy: economy)

        farm.bootstrap(in: context)
        economy.credit(500, reason: "seed", in: context)

        let t1 = ToolCatalog.all.first { $0.slug == "watering_can_ii" }!
        let t2 = ToolCatalog.all.first { $0.slug == "watering_can_iii" }!
        try tools.purchase(slug: t1.slug, in: context)
        try tools.purchase(slug: t2.slug, in: context)

        let bonus = tools.habitBonus(in: context)
        XCTAssertEqual(bonus, t1.habitBonus + t2.habitBonus)
    }

    @MainActor
    func test_tool_habitContributionIncludesBonus() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let tools = RealToolInteractor(economy: economy)
        let farm = RealFarmInteractor(economy: economy, tools: tools)

        farm.bootstrap(in: context)
        economy.credit(200, reason: "seed", in: context)

        let watering = ToolCatalog.all.first { $0.slug == "watering_can_ii" }!
        try tools.purchase(slug: watering.slug, in: context)

        let goal = DBModel.Goal(title: "Run", targetDate: Date())
        context.insert(goal)
        try farm.bindPlot(to: goal, in: context)

        let habit = DBModel.Habit(title: "Morning run", frequency: .daily)
        context.insert(habit)
        habit.goals = [goal]

        let beforeHealth = goal.plot!.health
        farm.applyHabitCompletion(habit, in: context)
        let afterHealth = goal.plot!.health

        let expectedGain = FarmTuning.habitContribution + watering.habitBonus
        XCTAssertEqual(afterHealth - beforeHealth, expectedGain)
    }

    @MainActor
    func test_tool_taskContributionIncludesBonus() throws {
        let context = try makeFarmContext()
        let economy = RealEconomyInteractor()
        let tools = RealToolInteractor(economy: economy)
        let farm = RealFarmInteractor(economy: economy, tools: tools)

        farm.bootstrap(in: context)
        economy.credit(200, reason: "seed", in: context)

        let hoe = ToolCatalog.all.first { $0.slug == "sharper_hoe_ii" }!
        try tools.purchase(slug: hoe.slug, in: context)

        let goal = DBModel.Goal(title: "Study", targetDate: Date())
        context.insert(goal)
        try farm.bindPlot(to: goal, in: context)

        let task = DBModel.Task(title: "Read chapter", priority: .normal)
        context.insert(task)
        task.goals = [goal]

        let beforeHealth = goal.plot!.health
        farm.applyTaskCompletion(task, in: context)
        let afterHealth = goal.plot!.health

        let expectedGain = FarmTuning.taskBaseContribution
            + (FarmTuning.taskPriorityBonus[.normal] ?? 0)
            + hoe.taskBonus
        XCTAssertEqual(afterHealth - beforeHealth, expectedGain)
    }
}

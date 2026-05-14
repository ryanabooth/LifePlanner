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

    func scheduleHabitReminder(habitID: UUID, title: String, time: Date) async {
        scheduled.append((habitID, title, time))
    }

    func cancelHabitReminder(habitID: UUID) async {
        cancelled.append(habitID)
    }

    func scheduleTaskDue(taskID: UUID, title: String, at fireDate: Date) async {
        scheduledTasks.append((taskID, title, fireDate))
    }

    func cancelTaskDue(taskID: UUID) async {
        cancelledTasks.append(taskID)
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
    private func makeFarmContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: DBModel.FarmState.self, DBModel.FarmPlot.self, DBModel.Goal.self,
                DBModel.Task.self, DBModel.Habit.self, DBModel.HabitLogEntry.self,
                DBModel.Quest.self,
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
        XCTAssertEqual(economy.balance(in: context), goldBefore + taskQuest.goldReward)
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
        XCTAssertEqual(economy.balance(in: context), goldBefore + harvestQuest.goldReward)
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
        // Log two entries earlier this week so target is met; logging today is unnecessary.
        habits.toggleDone(habit, on: weekStart, in: context)
        let dayBeforeToday = cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        if cal.isDate(dayBeforeToday, equalTo: Date(), toGranularity: .day) {
            // edge case: weekStart == today on Mondays. Use day-after-weekStart as
            // second log instead so target is still met without using today.
            habits.toggleDone(habit, on: cal.date(byAdding: .day, value: 1, to: weekStart)!, in: context)
        } else {
            habits.toggleDone(habit, on: dayBeforeToday, in: context)
        }

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
}

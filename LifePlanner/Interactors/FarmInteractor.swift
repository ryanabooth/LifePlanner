import Foundation
import SwiftData

enum FarmError: Error {
    case overCapacity
    case noFarmState
    case plotNotDead
    case insufficientGold
}

/// Tunable constants for the farm-sim economy. Pulled into one enum so balance
/// tweaks happen in one place. Numbers picked to fit a daily-habit cadence:
/// one full habit log offsets ~2 days of decay; a plot dies after about a week
/// of total neglect.
enum FarmTuning {
    static let healthMin = 0
    static let healthMax = 100
    static let matureThreshold = 80
    static let initialHealth = 50
    static let decayPerDay = 10
    static let daysWitheredBeforeDeath = 3

    // Contribution amounts.
    static let habitContribution = 20
    /// Base task contribution; priority adds bonus below.
    static let taskBaseContribution = 10
    static let taskPriorityBonus: [TaskPriority: Int] = [
        .low: 0,
        .normal: 5,
        .high: 10
    ]
    static let commonFieldContribution = 10

    // Economy.
    static let replantCost = 15

    // Weather side-effects.
    static let weatherSunshineGold = 15
    static let weatherStormDamage  = 30
    static func upgradeCost(currentCapacity: Int) -> Int {
        10 + currentCapacity * 5
    }
}

/// Owns plot lifecycle: bootstrap, allocation, health math, decay, death,
/// replant, and capacity upgrades. The single interactor in the codebase that
/// is allowed to mutate `FarmPlot` rows.
protocol FarmInteractor {
    /// Idempotent first-launch seed. Ensures exactly one `FarmState` and one
    /// common-field `FarmPlot` exist.
    func bootstrap(in context: ModelContext)

    /// Allocate a plot for the given goal at the next free grid slot. Throws
    /// `.overCapacity` if the user already has `plotCapacity` non-common-field
    /// plots.
    func bindPlot(to goal: DBModel.Goal, in context: ModelContext) throws

    /// Pump health into every plot bound to any of the given goals. Returns the
    /// number of plots that received a contribution.
    @discardableResult
    func applyContribution(amount: Int, toGoals goals: [DBModel.Goal], in context: ModelContext) -> Int

    /// Pump health into the singleton common-field plot.
    func applyContributionToCommonField(amount: Int, in context: ModelContext)

    /// Convenience: route a contribution from a habit. Each linked goal's plot
    /// receives `habitContribution`. If the habit has no linked goals, the
    /// common field receives `commonFieldContribution` instead.
    /// Returns the number of plots that newly reached the mature threshold.
    @discardableResult
    func applyHabitCompletion(_ habit: DBModel.Habit, in context: ModelContext) -> Int

    /// Convenience: route a contribution from a task. Linked goal plots get
    /// `taskBaseContribution + priority bonus`; unlinked tasks pump the
    /// common field.
    /// Returns the number of plots that newly reached the mature threshold.
    @discardableResult
    func applyTaskCompletion(_ task: DBModel.Task, in context: ModelContext) -> Int

    /// Apply decay for every whole day elapsed since `FarmState.lastDecayTick`.
    /// Idempotent within the same calendar day.
    func applyDailyDecay(now: Date, in context: ModelContext)

    /// Restore a dead plot to `.growing` at initial health. Costs gold.
    func replant(_ plot: DBModel.FarmPlot, in context: ModelContext) throws

    /// Increment `FarmState.plotCapacity` by one. Costs gold.
    func purchaseCapacity(in context: ModelContext) throws
}

final class RealFarmInteractor: FarmInteractor {

    private let economy: EconomyInteractor
    private let scheduler: NotificationScheduler
    private let achievements: AchievementInteractor
    private let tools: ToolInteractor
    private let calendar: Calendar

    init(
        economy: EconomyInteractor = RealEconomyInteractor(),
        scheduler: NotificationScheduler = StubNotificationScheduler(),
        achievements: AchievementInteractor = StubAchievementInteractor(),
        tools: ToolInteractor = StubToolInteractor(),
        calendar: Calendar = .current
    ) {
        self.economy = economy
        self.scheduler = scheduler
        self.achievements = achievements
        self.tools = tools
        self.calendar = calendar
    }

    // MARK: - Bootstrap

    func bootstrap(in context: ModelContext) {
        seedFarmStateIfNeeded(in: context)
        seedCommonFieldIfNeeded(in: context)
        if context.hasChanges {
            try? context.save()
        }
    }

    private func seedFarmStateIfNeeded(in context: ModelContext) {
        var fetch = FetchDescriptor<DBModel.FarmState>()
        fetch.fetchLimit = 1
        let existing = (try? context.fetch(fetch)) ?? []
        guard existing.isEmpty else { return }
        context.insert(DBModel.FarmState())
    }

    private func seedCommonFieldIfNeeded(in context: ModelContext) {
        // #Predicate can't compare enum cases directly, so fetch all and filter.
        let allPlots = (try? context.fetch(FetchDescriptor<DBModel.FarmPlot>())) ?? []
        guard !allPlots.contains(where: { $0.kind == .commonField }) else { return }
        context.insert(DBModel.FarmPlot(
            gridX: 0,
            gridY: 0,
            kind: .commonField,
            health: FarmTuning.healthMax,
            state: .mature
        ))
    }

    // MARK: - Plot binding

    func bindPlot(to goal: DBModel.Goal, in context: ModelContext) throws {
        // Idempotent: if a plot already exists for this goal, no-op.
        if goal.plot != nil { return }
        guard let state = farmState(in: context) else { throw FarmError.noFarmState }

        let allPlots = (try? context.fetch(FetchDescriptor<DBModel.FarmPlot>())) ?? []
        let userPlots = allPlots.filter { $0.kind != .commonField }
        guard userPlots.count < state.plotCapacity else { throw FarmError.overCapacity }

        let nextX = (userPlots.map(\.gridX).max() ?? 0) + 1
        let plot = DBModel.FarmPlot(
            gridX: nextX,
            gridY: 0,
            kind: goal.farmElementType,
            health: FarmTuning.initialHealth,
            state: .growing,
            goal: goal,
            lastContribution: Date()
        )
        context.insert(plot)
        goal.plot = plot
        goal.updatedAt = Date()
    }

    // MARK: - Contribution

    @discardableResult
    func applyContribution(amount: Int, toGoals goals: [DBModel.Goal], in context: ModelContext) -> Int {
        var count = 0
        for goal in goals {
            if let plot = goal.plot {
                applyContribution(amount: amount, to: plot)
                count += 1
            }
        }
        return count
    }

    func applyContributionToCommonField(amount: Int, in context: ModelContext) {
        let allPlots = (try? context.fetch(FetchDescriptor<DBModel.FarmPlot>())) ?? []
        guard let common = allPlots.first(where: { $0.kind == .commonField }) else { return }
        applyContribution(amount: amount, to: common)
    }

    @discardableResult
    func applyHabitCompletion(_ habit: DBModel.Habit, in context: ModelContext) -> Int {
        let weather = activeWeatherKind(in: context)
        let toolBonus = tools.habitBonus(in: context)
        let goals = habit.goals ?? []
        if goals.isEmpty {
            let base = FarmTuning.commonFieldContribution + toolBonus
            let amount = max(1, Int((Double(base) * weather.habitMultiplier).rounded()))
            applyContributionToCommonField(amount: amount, in: context)
            return 0
        }
        let base = FarmTuning.habitContribution + toolBonus
        let amount = max(1, Int((Double(base) * weather.habitMultiplier).rounded()))
        let newlyMatured = goals.reduce(0) { sum, goal in
            guard let plot = goal.plot else { return sum }
            return sum + (applyContribution(amount: amount, to: plot) ? 1 : 0)
        }
        if newlyMatured > 0, let state = farmState(in: context) {
            state.totalMatureTransitions += newlyMatured
        }
        return newlyMatured
    }

    @discardableResult
    func applyTaskCompletion(_ task: DBModel.Task, in context: ModelContext) -> Int {
        let weather = activeWeatherKind(in: context)
        let toolBonus = tools.taskBonus(in: context)
        let base = FarmTuning.taskBaseContribution + (FarmTuning.taskPriorityBonus[task.priority] ?? 0) + toolBonus
        let amount = max(1, Int((Double(base) * weather.taskMultiplier).rounded()))
        let goals = task.goals ?? []
        if goals.isEmpty {
            applyContributionToCommonField(amount: amount, in: context)
            return 0
        }
        let newlyMatured = goals.reduce(0) { sum, goal in
            guard let plot = goal.plot else { return sum }
            return sum + (applyContribution(amount: amount, to: plot) ? 1 : 0)
        }
        if newlyMatured > 0, let state = farmState(in: context) {
            state.totalMatureTransitions += newlyMatured
        }
        return newlyMatured
    }

    private func activeWeatherKind(in context: ModelContext) -> WeatherKind {
        let now = Date()
        let all = (try? context.fetch(FetchDescriptor<DBModel.WeatherEvent>())) ?? []
        return all.first { $0.startedAt <= now && $0.expiresAt > now }?.kind ?? .clear
    }

    /// Returns `true` if this contribution caused the plot to newly reach mature.
    @discardableResult
    private func applyContribution(amount: Int, to plot: DBModel.FarmPlot) -> Bool {
        guard plot.state != .dead else { return false }
        let wasMature = plot.state == .mature
        plot.health = clamp(plot.health + amount)
        plot.lastContribution = Date()
        plot.updatedAt = Date()
        // Revive withered plots when health crosses back above zero.
        if plot.state == .withered, plot.health > 0 {
            plot.state = plot.health >= FarmTuning.matureThreshold ? .mature : .growing
        } else if plot.state == .growing, plot.health >= FarmTuning.matureThreshold {
            plot.state = .mature
        }
        return !wasMature && plot.state == .mature
    }

    // MARK: - Decay

    func applyDailyDecay(now: Date, in context: ModelContext) {
        guard let state = farmState(in: context) else { return }
        let today = calendar.startOfDay(for: now)
        let lastTick = state.lastDecayTick.map { calendar.startOfDay(for: $0) }
        let daysElapsed: Int
        if let lastTick {
            daysElapsed = calendar.dateComponents([.day], from: lastTick, to: today).day ?? 0
        } else {
            // First run — set the baseline without decaying anything.
            daysElapsed = 0
        }
        defer {
            state.lastDecayTick = today
            state.updatedAt = Date()
        }
        guard daysElapsed > 0 else { return }

        let decayMultiplier = activeWeatherKind(in: context).decayMultiplier
        let allPlots = (try? context.fetch(FetchDescriptor<DBModel.FarmPlot>())) ?? []
        for plot in allPlots where plot.kind != .commonField {
            decay(plot: plot, days: daysElapsed, multiplier: decayMultiplier)
        }
        // Common field decays at half rate so it slowly drifts but rarely dies.
        if let common = allPlots.first(where: { $0.kind == .commonField }) {
            decay(plot: common, days: max(1, daysElapsed / 2), multiplier: decayMultiplier)
        }
    }

    private func decay(plot: DBModel.FarmPlot, days: Int, multiplier: Double = 1.0) {
        guard plot.state != .dead else { return }
        let prevState = plot.state
        let totalDecay = Int((Double(days * FarmTuning.decayPerDay) * multiplier).rounded())
        plot.health = clamp(plot.health - totalDecay)
        plot.updatedAt = Date()

        if plot.health <= 0 {
            if plot.state == .withered {
                // Already withered — promote to dead after N additional days.
                let witheredSince = plot.lastContribution ?? plot.createdAt
                let daysSince = calendar.dateComponents([.day], from: witheredSince, to: Date()).day ?? 0
                if daysSince >= FarmTuning.daysWitheredBeforeDeath {
                    plot.state = .dead
                }
            } else {
                plot.state = .withered
            }
        } else if plot.health < FarmTuning.matureThreshold, plot.state == .mature {
            plot.state = .growing
        }

        schedulePlotNotificationIfNeeded(plot: plot, prevState: prevState)
    }

    private func schedulePlotNotificationIfNeeded(
        plot: DBModel.FarmPlot,
        prevState: PlotState
    ) {
        guard plot.kind != .commonField else { return }
        let id = plot.id
        let label = plot.kind.label

        if prevState != .withered, plot.state == .withered {
            Task.detached { [scheduler] in
                await scheduler.schedulePlotAlert(
                    plotID: id,
                    title: "\(label) is wilting",
                    body: "Log a habit or complete a task before it dies.",
                    fireAt: Calendar.current.nextMorning
                )
            }
        } else if prevState != .dead, plot.state == .dead {
            Task.detached { [scheduler] in
                await scheduler.schedulePlotAlert(
                    plotID: id,
                    title: "\(label) has died",
                    body: "Open the app to replant it and get back on track.",
                    fireAt: Calendar.current.nextMorning
                )
            }
        }
    }

    // MARK: - Replant + upgrade

    func replant(_ plot: DBModel.FarmPlot, in context: ModelContext) throws {
        guard plot.state == .dead || plot.state == .withered else { throw FarmError.plotNotDead }
        try economy.spend(FarmTuning.replantCost, reason: "replant", in: context)
        plot.health = FarmTuning.initialHealth
        plot.state = .growing
        plot.lastContribution = Date()
        plot.updatedAt = Date()
        if let state = farmState(in: context) {
            state.totalReplants += 1
        }
        let id = plot.id
        Task.detached { [scheduler] in await scheduler.cancelPlotAlert(plotID: id) }
        achievements.checkAll(in: context)
    }

    func purchaseCapacity(in context: ModelContext) throws {
        guard let state = farmState(in: context) else { throw FarmError.noFarmState }
        let cost = FarmTuning.upgradeCost(currentCapacity: state.plotCapacity)
        try economy.spend(cost, reason: "capacity-upgrade", in: context)
        state.plotCapacity += 1
        state.updatedAt = Date()
    }

    // MARK: - Helpers

    private func farmState(in context: ModelContext) -> DBModel.FarmState? {
        var fetch = FetchDescriptor<DBModel.FarmState>()
        fetch.fetchLimit = 1
        return (try? context.fetch(fetch))?.first
    }

    private func clamp(_ value: Int) -> Int {
        max(FarmTuning.healthMin, min(FarmTuning.healthMax, value))
    }
}

private extension Calendar {
    /// 9 AM tomorrow — used as the fire time for plot-health alerts.
    var nextMorning: Date {
        let tomorrow = date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

final class StubFarmInteractor: FarmInteractor {
    func bootstrap(in context: ModelContext) {}
    func bindPlot(to goal: DBModel.Goal, in context: ModelContext) throws {}
    @discardableResult
    func applyContribution(amount: Int, toGoals goals: [DBModel.Goal], in context: ModelContext) -> Int { 0 }
    func applyContributionToCommonField(amount: Int, in context: ModelContext) {}
    @discardableResult
    func applyHabitCompletion(_ habit: DBModel.Habit, in context: ModelContext) -> Int { 0 }
    @discardableResult
    func applyTaskCompletion(_ task: DBModel.Task, in context: ModelContext) -> Int { 0 }
    func applyDailyDecay(now: Date, in context: ModelContext) {}
    func replant(_ plot: DBModel.FarmPlot, in context: ModelContext) throws {}
    func purchaseCapacity(in context: ModelContext) throws {}
}

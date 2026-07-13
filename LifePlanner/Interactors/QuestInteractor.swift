import Foundation
import SwiftData

enum QuestError: Error {
    case insufficientGold(have: Int, need: Int)
    case notSatisfiable
    case alreadyClaimed
}

enum QuestTuning {
    static let slotsPerDay = 3
    /// Slot index reserved for the weekly bonus quest.
    static let weeklySlot = 3

    static let taskBaseReward = 5
    static let taskPriorityBonus: [TaskPriority: Int] = [
        .low: 0,
        .normal: 5,
        .high: 10
    ]
    static let habitReward = 5
    static let commonFieldReward = 3
    static let harvestMatureThreshold = 2
    static let harvestMatureReward = 15

    /// Weekly quest: push this many plots to mature during the week to claim.
    static let weeklyHarvestTarget = 5
    static let weeklyHarvestReward = 30

    static let rerollBaseCost = 3
    static let rerollCostStep = 2

    static func rerollCost(for rerollCount: Int) -> Int {
        rerollBaseCost + rerollCount * rerollCostStep
    }
}

protocol QuestInteractor {
    /// Idempotent for the day. Returns up to 3 quests for `day`; creates any missing slots.
    @discardableResult
    func rollDaily(on day: Date, in context: ModelContext) -> [DBModel.Quest]

    /// Re-roll a single quest slot in place. Costs gold; replaces the slot's
    /// `referenceID`, `kind`, `goldReward`, and bumps `rerollCount`.
    func reroll(_ quest: DBModel.Quest, in context: ModelContext) throws

    /// Mark a quest completed and credit its reward. Throws if the underlying
    /// task/habit/common-field hasn't been satisfied.
    func claim(_ quest: DBModel.Quest, in context: ModelContext) throws

    /// Auto-claim any active quest whose `referenceID` matches. Silent if none.
    /// Called from Habits/Tasks `toggleDone` so completion in any UI surface
    /// pays out without an explicit claim step.
    func notifyCompletion(referenceID: UUID, in context: ModelContext)

    /// Auto-claim any active `commonFieldTend` quest for today. Called whenever
    /// an unlinked task or habit is completed (any common-field health increase
    /// satisfies the quest regardless of the field's current health level).
    func notifyCommonFieldTend(in context: ModelContext)

    /// Auto-claim any active `harvestMature` quests whose farm-state condition
    /// is now satisfied. Called after every farm contribution.
    func checkFarmQuests(in context: ModelContext)

    /// Replace any `.commonFieldTend` placeholder slots with real task/habit
    /// candidates that have become available since today's batch was rolled.
    /// Idempotent — does nothing when there are no upgrade candidates.
    /// Called from `TasksInteractor.add` / `HabitsInteractor.add` so newly-
    /// created items appear in today's quest log immediately.
    func refreshTodaysCommonFieldSlots(in context: ModelContext)

    /// Roll the weekly harvest quest for the ISO week containing `day`.
    /// Idempotent — does nothing if a slot-3 quest already exists this week.
    @discardableResult
    func rollWeekly(on day: Date, in context: ModelContext) -> DBModel.Quest?

    /// Increment progress on the active weekly harvest quest by `count` newly-matured
    /// plots. Auto-claims the quest once progress reaches `progressTarget`.
    func trackMatureTransitions(count: Int, in context: ModelContext)

    /// Set state = .expired on every still-active quest dated before `day`.
    func expireOldQuests(on day: Date, in context: ModelContext)
}

final class RealQuestInteractor: QuestInteractor {

    private let economy: EconomyInteractor
    private let calendar: Calendar
    private let rng: () -> Int

    init(
        economy: EconomyInteractor = RealEconomyInteractor(),
        calendar: Calendar = .current,
        // Injectable for deterministic tests; production uses a real random seed.
        rng: @escaping () -> Int = { Int.random(in: 0..<Int.max) }
    ) {
        self.economy = economy
        self.calendar = calendar
        self.rng = rng
    }

    // MARK: - rollDaily

    @discardableResult
    func rollDaily(on day: Date, in context: ModelContext) -> [DBModel.Quest] {
        let today = calendar.startOfDay(for: day)
        let existing = fetchQuests(on: today, in: context)
        if existing.count >= QuestTuning.slotsPerDay {
            return existing.sorted { $0.slot < $1.slot }
        }

        let usedRefs = Set(existing.compactMap(\.referenceID))
        let pool = candidatePool(today: today, excluding: usedRefs, in: context)
        var picks = shuffled(pool, count: QuestTuning.slotsPerDay - existing.count)

        var quests = existing
        let occupiedSlots = Set(existing.map(\.slot))
        for slot in 0..<QuestTuning.slotsPerDay where !occupiedSlots.contains(slot) {
            let candidate = picks.popLast() ?? .commonField
            let quest = makeQuest(slot: slot, day: today, from: candidate)
            context.insert(quest)
            quests.append(quest)
        }
        return quests.sorted { $0.slot < $1.slot }
    }

    // MARK: - reroll

    func reroll(_ quest: DBModel.Quest, in context: ModelContext) throws {
        let cost = QuestTuning.rerollCost(for: quest.rerollCount)
        do {
            try economy.spend(cost, reason: "quest-reroll", in: context)
        } catch EconomyError.insufficientGold(let have, let need) {
            throw QuestError.insufficientGold(have: have, need: need)
        }
        Task { @MainActor in SoundPlayer.shared.play(.questReroll) }
        Task { @MainActor in HapticPlayer.shared.tap() }

        let day = calendar.startOfDay(for: quest.day)
        let todays = fetchQuests(on: day, in: context)
        let used = Set(todays.compactMap(\.referenceID))
            .union([quest.referenceID].compactMap { $0 })
        let pool = candidatePool(today: day, excluding: used, in: context)
        let pick = shuffled(pool, count: 1).first ?? .commonField
        apply(candidate: pick, to: quest)
        quest.rerollCount += 1
        quest.state = .active
        quest.updatedAt = Date()
    }

    // MARK: - claim / notifyCompletion

    func claim(_ quest: DBModel.Quest, in context: ModelContext) throws {
        guard quest.state == .active else { throw QuestError.alreadyClaimed }
        guard isSatisfied(quest, in: context) else { throw QuestError.notSatisfiable }
        credit(quest, in: context)
    }

    func notifyCompletion(referenceID: UUID, in context: ModelContext) {
        let today = calendar.startOfDay(for: Date())
        let todays = fetchQuests(on: today, in: context)
        for quest in todays where quest.state == .active && quest.referenceID == referenceID {
            credit(quest, in: context)
        }
    }

    func notifyCommonFieldTend(in context: ModelContext) {
        let today = calendar.startOfDay(for: Date())
        let todays = fetchQuests(on: today, in: context)
        if let quest = todays.first(where: { $0.state == .active && $0.kind == .commonFieldTend }) {
            credit(quest, in: context)
        }
    }

    private func credit(_ quest: DBModel.Quest, in context: ModelContext) {
        quest.state = .completed
        quest.updatedAt = Date()
        economy.credit(quest.goldReward, reason: "quest-\(quest.kind)", in: context)
        Task { @MainActor in SoundPlayer.shared.play(.questClaim) }
        Task { @MainActor in HapticPlayer.shared.success() }
    }

    // MARK: - refreshTodaysCommonFieldSlots

    func refreshTodaysCommonFieldSlots(in context: ModelContext) {
        let today = calendar.startOfDay(for: Date())
        let todays = fetchQuests(on: today, in: context)
        let placeholders = todays.filter { $0.kind == .commonFieldTend && $0.state == .active }
        guard !placeholders.isEmpty else { return }

        // Exclude refs already in any of today's slots so we don't double-book.
        let usedRefs = Set(todays.compactMap(\.referenceID))
        let pool = candidatePool(today: today, excluding: usedRefs, in: context)
        guard !pool.isEmpty else { return }

        var picks = shuffled(pool, count: placeholders.count)
        for slot in placeholders {
            guard let candidate = picks.popLast() else { break }
            apply(candidate: candidate, to: slot)
            slot.updatedAt = Date()
            // Do not bump rerollCount — this is an auto-upgrade, not a user reroll.
        }
    }

    // MARK: - checkFarmQuests

    func checkFarmQuests(in context: ModelContext) {
        let today = calendar.startOfDay(for: Date())
        let todays = fetchQuests(on: today, in: context)
        for quest in todays where quest.state == .active && quest.kind == .harvestMature {
            if isSatisfied(quest, in: context) { credit(quest, in: context) }
        }
    }

    // MARK: - rollWeekly

    @discardableResult
    func rollWeekly(on day: Date, in context: ModelContext) -> DBModel.Quest? {
        let start = weekStart(for: day)
        let existing = fetchWeeklyQuests(weekStart: start, in: context)
        guard existing.isEmpty else { return existing.first }
        let quest = DBModel.Quest(
            day: start,
            slot: QuestTuning.weeklySlot,
            kind: .weeklyHarvest,
            goldReward: QuestTuning.weeklyHarvestReward,
            progressTarget: QuestTuning.weeklyHarvestTarget
        )
        context.insert(quest)
        return quest
    }

    // MARK: - trackMatureTransitions

    func trackMatureTransitions(count: Int, in context: ModelContext) {
        guard count > 0 else { return }
        let start = weekStart(for: Date())
        for quest in fetchWeeklyQuests(weekStart: start, in: context)
            where quest.state == .active && quest.kind == .weeklyHarvest {
            quest.progress = min(quest.progress + count, quest.progressTarget)
            quest.updatedAt = Date()
            if quest.progress >= quest.progressTarget {
                credit(quest, in: context)
            }
        }
    }

    // MARK: - expireOldQuests

    func expireOldQuests(on day: Date, in context: ModelContext) {
        let today = calendar.startOfDay(for: day)
        let thisWeekStart = weekStart(for: day)
        let all = (try? context.fetch(FetchDescriptor<DBModel.Quest>())) ?? []
        for quest in all where quest.state == .active {
            // Weekly quests stay active for the whole ISO week; daily quests
            // expire once their day has passed.
            let stale = quest.kind == .weeklyHarvest
                ? quest.day < thisWeekStart
                : quest.day < today
            if stale {
                quest.state = .expired
                quest.updatedAt = Date()
            }
        }
    }

    // MARK: - Candidate generation

    /// Internal candidate descriptor — what a quest slot can hold before persistence.
    private enum Candidate {
        case task(DBModel.Task)
        case habit(DBModel.Habit)
        case commonField
        case harvestMature
    }

    private func candidatePool(
        today: Date,
        excluding usedRefs: Set<UUID>,
        in context: ModelContext
    ) -> [Candidate] {
        var pool: [Candidate] = []
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        // Tasks: open + due today/overdue + not already a quest slot today.
        let openTasks = (try? context.fetch(FetchDescriptor<DBModel.Task>(
            predicate: #Predicate { $0.isDone == false }
        ))) ?? []
        for task in openTasks where !usedRefs.contains(task.id) {
            guard let due = task.dueDate, due < endOfToday else { continue }
            guard questEligible(goals: task.goals) else { continue }
            pool.append(.task(task))
        }

        // Habits: non-archived + cadence target not yet met + not already used.
        // Daily habits drop out once today's log lands; weekly habits drop out
        // once the per-week target is met, regardless of which days were used.
        // Weekly habits with the target still open also drop out if today already
        // has a log (one quest per day max).
        let activeHabits = (try? context.fetch(FetchDescriptor<DBModel.Habit>(
            predicate: #Predicate { $0.archived == false }
        ))) ?? []
        for habit in activeHabits where !usedRefs.contains(habit.id) {
            if habit.isWeekComplete(containing: today, calendar: calendar) { continue }
            if habit.isDone(on: today, calendar: calendar) { continue }
            guard questEligible(goals: habit.goals) else { continue }
            pool.append(.habit(habit))
        }

        // harvestMature: include when the user has enough living goal plots that
        // reaching the threshold is plausible, and today doesn't already have one.
        let allPlots = (try? context.fetch(FetchDescriptor<DBModel.FarmPlot>())) ?? []
        let livingGoalPlots = allPlots.filter { $0.kind != .commonField && $0.state != .dead }
        let todayAlreadyHasHarvest = fetchQuests(on: today, in: context)
            .contains { $0.kind == .harvestMature }
        if livingGoalPlots.count >= QuestTuning.harvestMatureThreshold, !todayAlreadyHasHarvest {
            pool.append(.harvestMature)
        }

        return pool
    }

    /// A task/habit is quest-eligible if it's unlinked (feeds the common field)
    /// or linked to at least one active goal. Items tied only to paused/done/
    /// abandoned goals are excluded — no point questing toward a goal on hold.
    private func questEligible(goals: [DBModel.Goal]?) -> Bool {
        let goals = goals ?? []
        if goals.isEmpty { return true }
        return goals.contains { $0.status == .active }
    }

    private func shuffled(_ pool: [Candidate], count: Int) -> [Candidate] {
        guard !pool.isEmpty, count > 0 else { return [] }
        var copy = pool
        // Fisher-Yates using injected RNG so tests can be deterministic.
        for i in stride(from: copy.count - 1, through: 1, by: -1) {
            let j = rng() % (i + 1)
            copy.swapAt(i, j)
        }
        return Array(copy.prefix(count))
    }

    private func makeQuest(slot: Int, day: Date, from candidate: Candidate) -> DBModel.Quest {
        let quest = DBModel.Quest(day: day, slot: slot)
        apply(candidate: candidate, to: quest)
        return quest
    }

    private func apply(candidate: Candidate, to quest: DBModel.Quest) {
        switch candidate {
        case .task(let task):
            quest.kind = .taskDue
            quest.referenceID = task.id
            quest.goldReward = QuestTuning.taskBaseReward
                + (QuestTuning.taskPriorityBonus[task.priority] ?? 0)
        case .habit(let habit):
            quest.kind = .habitDue
            quest.referenceID = habit.id
            quest.goldReward = QuestTuning.habitReward
        case .commonField:
            quest.kind = .commonFieldTend
            quest.referenceID = nil
            quest.goldReward = QuestTuning.commonFieldReward
        case .harvestMature:
            quest.kind = .harvestMature
            quest.referenceID = nil
            quest.goldReward = QuestTuning.harvestMatureReward
        }
    }

    // MARK: - Satisfaction check

    private func isSatisfied(_ quest: DBModel.Quest, in context: ModelContext) -> Bool {
        switch quest.kind {
        case .taskDue:
            guard let refID = quest.referenceID else { return false }
            let match = (try? context.fetch(FetchDescriptor<DBModel.Task>(
                predicate: #Predicate { $0.id == refID }
            )))?.first
            return match?.isDone == true
        case .habitDue:
            guard let refID = quest.referenceID else { return false }
            let match = (try? context.fetch(FetchDescriptor<DBModel.Habit>(
                predicate: #Predicate { $0.id == refID }
            )))?.first
            return match?.isDone(on: quest.day, calendar: calendar) == true
        case .commonFieldTend:
            // Considered satisfiable if the common field is at least mature
            // (encourages keeping it watered with miscellaneous completions).
            let plots = (try? context.fetch(FetchDescriptor<DBModel.FarmPlot>())) ?? []
            return plots.first { $0.kind == .commonField }?
                .health ?? 0 >= FarmTuning.matureThreshold
        case .harvestMature:
            let plots = (try? context.fetch(FetchDescriptor<DBModel.FarmPlot>())) ?? []
            let matureCount = plots.filter {
                $0.kind != .commonField && $0.state == .mature
            }.count
            return matureCount >= QuestTuning.harvestMatureThreshold
        case .weeklyHarvest:
            return quest.progress >= quest.progressTarget
        }
    }

    // MARK: - Helpers

    private func fetchQuests(on day: Date, in context: ModelContext) -> [DBModel.Quest] {
        let today = calendar.startOfDay(for: day)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let fetch = FetchDescriptor<DBModel.Quest>(
            predicate: #Predicate { $0.day >= today && $0.day < tomorrow }
        )
        return (try? context.fetch(fetch)) ?? []
    }

    private func fetchWeeklyQuests(weekStart: Date, in context: ModelContext) -> [DBModel.Quest] {
        let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
        let slot = QuestTuning.weeklySlot
        let fetch = FetchDescriptor<DBModel.Quest>(
            predicate: #Predicate { $0.slot == slot && $0.day >= weekStart && $0.day < weekEnd }
        )
        return (try? context.fetch(fetch)) ?? []
    }

    private func weekStart(for date: Date) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }
}

final class StubQuestInteractor: QuestInteractor {
    @discardableResult
    func rollDaily(on day: Date, in context: ModelContext) -> [DBModel.Quest] { [] }
    func reroll(_ quest: DBModel.Quest, in context: ModelContext) throws {}
    func claim(_ quest: DBModel.Quest, in context: ModelContext) throws {}
    func notifyCompletion(referenceID: UUID, in context: ModelContext) {}
    func notifyCommonFieldTend(in context: ModelContext) {}
    func checkFarmQuests(in context: ModelContext) {}
    func refreshTodaysCommonFieldSlots(in context: ModelContext) {}
    @discardableResult
    func rollWeekly(on day: Date, in context: ModelContext) -> DBModel.Quest? { nil }
    func trackMatureTransitions(count: Int, in context: ModelContext) {}
    func expireOldQuests(on day: Date, in context: ModelContext) {}
}

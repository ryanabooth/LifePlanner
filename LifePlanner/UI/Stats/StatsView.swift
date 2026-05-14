import SwiftUI
import SwiftData
import Charts

// MARK: - Local data shapes

private struct CompletionPoint: Identifiable {
    let id = UUID()
    let date: Date
    let cumulative: Int
    let habitTitle: String
}

private struct GoalContrib: Identifiable {
    let id: UUID
    let title: String
    let count: Int
}

private struct QuestKindStat: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
}

// MARK: - Main view

struct StatsView: View {

    @Query private var habits:    [DBModel.Habit]
    @Query private var entries:   [DBModel.HabitLogEntry]
    @Query private var tasks:     [DBModel.Task]
    @Query private var goals:     [DBModel.Goal]
    @Query private var quests:    [DBModel.Quest]
    @Query private var plots:     [DBModel.FarmPlot]
    @Query private var farmState: [DBModel.FarmState]

    @State private var window: Int = 30

    var body: some View {
        List {
            habitCompletionSection
            streaksSection
            goalContributionsSection
            totalsSection
            questHistorySection
        }
        .listSectionSpacing(12)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Habit completion

    private var habitCompletionSection: some View {
        Section {
            Picker("Window", selection: $window) {
                Text("30 days").tag(30)
                Text("90 days").tag(90)
            }
            .pickerStyle(.segmented)

            if chartData.isEmpty {
                emptyLabel("Start logging habits to see your chart.")
            } else {
                Chart(chartData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Completions", point.cumulative)
                    )
                    .foregroundStyle(by: .value("Habit", point.habitTitle))
                    .interpolationMethod(.stepEnd)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: window == 30 ? 7 : 21)) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 200)
            }
        } header: {
            Text("Habit Completion")
        }
    }

    private var chartData: [CompletionPoint] {
        let cal = Calendar.current
        let now = Date()
        guard let cutoff = cal.date(byAdding: .day, value: -window, to: cal.startOfDay(for: now)) else { return [] }
        let inWindow = entries.filter { $0.date >= cutoff }
        guard !inWindow.isEmpty else { return [] }

        let byHabit = Dictionary(grouping: inWindow) { $0.habit?.title ?? "Unknown" }
        var points: [CompletionPoint] = []
        for (title, habitEntries) in byHabit {
            points.append(CompletionPoint(date: cutoff, cumulative: 0, habitTitle: title))
            var cum = 0
            for e in habitEntries.sorted(by: { $0.date < $1.date }) {
                cum += 1
                points.append(CompletionPoint(date: e.date, cumulative: cum, habitTitle: title))
            }
        }
        return points
    }

    // MARK: - Streaks

    private var streaksSection: some View {
        let active = habits.filter { !$0.archived && ($0.longestStreak > 0 || $0.currentStreak > 0) }
        return Section("Streaks") {
            if active.isEmpty {
                emptyLabel("Complete habits to build streaks.")
            } else {
                Chart(active) { habit in
                    BarMark(
                        x: .value("Streak", habit.longestStreak),
                        y: .value("Habit", habit.title)
                    )
                    .foregroundStyle(.orange.gradient)
                    .cornerRadius(4)

                    if habit.currentStreak < habit.longestStreak {
                        PointMark(
                            x: .value("Current", habit.currentStreak),
                            y: .value("Habit", habit.title)
                        )
                        .foregroundStyle(.red)
                        .symbolSize(60)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let milestones = [7, 14, 30, 60, 90]
                        ForEach(milestones, id: \.self) { m in
                            if let origin = proxy.position(forX: m) {
                                let x = origin + geo[proxy.plotFrame!].minX
                                Path { path in
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: geo[proxy.plotFrame!].maxY))
                                }
                                .stroke(Color.secondary.opacity(0.3),
                                        style: StrokeStyle(lineWidth: 1, dash: [3]))
                            }
                        }
                    }
                }
                .chartXAxisLabel("Days")
                .frame(height: max(56, CGFloat(active.count) * 44))
            }
        }
    }

    // MARK: - Goal contributions

    private var goalContributionsSection: some View {
        let contribs = goalContributions
        return Section("Goal Contributions") {
            if contribs.isEmpty {
                emptyLabel("Link habits or tasks to goals to track contributions.")
            } else {
                Chart(contribs.prefix(8)) { item in
                    BarMark(
                        x: .value("Contributions", item.count),
                        y: .value("Goal", item.title)
                    )
                    .foregroundStyle(.green.gradient)
                    .cornerRadius(4)
                }
                .chartXAxisLabel("Total contributions")
                .frame(height: max(56, CGFloat(min(contribs.count, 8)) * 40))
            }
        }
    }

    private var goalContributions: [GoalContrib] {
        goals.compactMap { goal -> GoalContrib? in
            let habitContribs = (goal.linkedHabits ?? []).reduce(0) { $0 + ($1.entries?.count ?? 0) }
            let taskContribs  = (goal.linkedTasks ?? []).filter { $0.isDone }.count
            let total = habitContribs + taskContribs
            guard total > 0 else { return nil }
            return GoalContrib(id: goal.id, title: goal.title, count: total)
        }
        .sorted { $0.count > $1.count }
    }

    // MARK: - Totals

    private var totalsSection: some View {
        Section("Totals") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(icon: "checkmark.circle", label: "Tasks done",
                         value: "\(tasks.filter { $0.isDone }.count)")
                StatTile(icon: "calendar", label: "Habits logged",
                         value: "\(entries.count)")
                StatTile(icon: "dollarsign.circle", label: "Current gold",
                         value: "\(farmState.first?.gold ?? 0) 🪙")
                StatTile(icon: "leaf.fill", label: "Dead plots",
                         value: "\(plots.filter { $0.state == .dead }.count)")
                StatTile(icon: "clock", label: "Days active",
                         value: "\(daysActive)")
                StatTile(icon: "star.circle", label: "Quests done",
                         value: "\(quests.filter { $0.state == .completed }.count)")
            }
            .padding(.vertical, 4)
        }
    }

    private var daysActive: Int {
        let dates = habits.map { $0.createdAt } + tasks.map { $0.createdAt }
        guard let earliest = dates.min() else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: earliest, to: Date()).day ?? 0)
    }

    // MARK: - Quest history

    private var questHistorySection: some View {
        let stats = questKindStats
        return Section("Quest History") {
            if stats.isEmpty {
                emptyLabel("Complete quests to see a breakdown here.")
            } else {
                HStack(spacing: 0) {
                    Chart(stats) { item in
                        SectorMark(
                            angle: .value("Count", item.count),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Kind", item.label))
                        .cornerRadius(4)
                    }
                    .chartLegend(position: .trailing, alignment: .center, spacing: 8)
                    .frame(height: 180)
                }
            }
        }
    }

    private var questKindStats: [QuestKindStat] {
        let completed = quests.filter { $0.state == .completed }
        guard !completed.isEmpty else { return [] }
        let grouped = Dictionary(grouping: completed) { $0.kind }
        return grouped.map { kind, qs in
            QuestKindStat(label: kind.statsLabel, count: qs.count)
        }.sorted { $0.count > $1.count }
    }

    // MARK: - Helpers

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - QuestKind stats label

private extension QuestKind {
    var statsLabel: String {
        switch self {
        case .taskDue:        return "Task"
        case .habitDue:       return "Habit"
        case .commonFieldTend: return "Common Field"
        case .harvestMature:  return "Harvest"
        case .weeklyHarvest:  return "Weekly"
        }
    }
}

#Preview {
    NavigationStack {
        StatsView()
            .modelContainer(
                for: [
                    DBModel.Task.self, DBModel.Habit.self, DBModel.HabitLogEntry.self,
                    DBModel.Goal.self, DBModel.Quest.self, DBModel.FarmPlot.self,
                    DBModel.FarmState.self
                ],
                inMemory: true
            )
    }
}

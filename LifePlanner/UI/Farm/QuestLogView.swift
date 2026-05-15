import SwiftUI
import SwiftData

/// Today's 3 quests with claim and re-roll affordances. Quest rolls happen on
/// app foreground (`SystemEventsHandler.runDailyTick`); this view is read-only
/// against today's `Quest` rows plus the user-initiated re-roll mutation.
struct QuestLogView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\DBModel.Quest.slot)])
    private var allQuests: [DBModel.Quest]

    @Query private var farmStates: [DBModel.FarmState]
    @Query private var tasks: [DBModel.Task]
    @Query private var habits: [DBModel.Habit]

    private var todaysQuests: [DBModel.Quest] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        return allQuests.filter { $0.day >= today && $0.day < tomorrow }
    }

    private var weeklyQuest: DBModel.Quest? {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        guard let weekStart = cal.date(from: comps),
              let weekEnd = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart)
        else { return nil }
        return allQuests.first {
            $0.slot == QuestTuning.weeklySlot && $0.day >= weekStart && $0.day < weekEnd
        }
    }

    private var gold: Int { farmStates.first?.gold ?? 0 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("🪙 Gold")
                        Spacer()
                        Text("\(gold)").bold()
                    }
                }

                Section {
                    if todaysQuests.isEmpty {
                        Text("No quests rolled yet — relaunch the app to roll today's batch.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(todaysQuests) { quest in
                            QuestRow(
                                quest: quest,
                                taskTitle: lookupTaskTitle(for: quest),
                                habitTitle: lookupHabitTitle(for: quest),
                                canAfford: gold >= QuestTuning.rerollCost(for: quest.rerollCount),
                                onReroll: { try? injected.interactors.quests.reroll(quest, in: modelContext) }
                            )
                        }
                    }
                } header: {
                    Text("Today's Quests")
                } footer: {
                    Text("Completing the underlying task or habit auto-claims the matching quest. Re-roll a slot to swap it for a different ask — cost grows each time.")
                }

                Section {
                    if let wq = weeklyQuest {
                        WeeklyQuestRow(quest: wq)
                    } else {
                        Text("Weekly quest not rolled yet — open the app tomorrow.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("This Week")
                } footer: {
                    Text("Push \(QuestTuning.weeklyHarvestTarget) plots to mature this week to claim the bonus reward.")
                }
            }
            .navigationTitle("Quests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Lookup helpers

    private func lookupTaskTitle(for quest: DBModel.Quest) -> String? {
        guard quest.kind == .taskDue, let refID = quest.referenceID else { return nil }
        return tasks.first { $0.id == refID }?.title
    }

    private func lookupHabitTitle(for quest: DBModel.Quest) -> String? {
        guard quest.kind == .habitDue, let refID = quest.referenceID else { return nil }
        return habits.first { $0.id == refID }?.title
    }
}

private struct QuestRow: View {
    let quest: DBModel.Quest
    let taskTitle: String?
    let habitTitle: String?
    let canAfford: Bool
    let onReroll: () -> Void

    @State private var flashGreen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(headline)
                    .font(.body)
                    .strikethrough(quest.state == .completed)
                Spacer()
                stateBadge
            }
            HStack {
                Text("🪙 \(quest.goldReward)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if quest.state == .active {
                    Button {
                        onReroll()
                    } label: {
                        Label("Re-roll (\(QuestTuning.rerollCost(for: quest.rerollCount)))", systemImage: "dice")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canAfford)
                    .accessibilityLabel("Reroll quest, costs \(QuestTuning.rerollCost(for: quest.rerollCount)) gold")
                    .accessibilityHint(canAfford ? "" : "Not enough gold")
                }
            }
        }
        .padding(.vertical, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(flashGreen ? 0.22 : 0))
                .allowsHitTesting(false)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
        .onChange(of: quest.state) { _, newState in
            guard newState == .completed else { return }
            if reduceMotion {
                flashGreen = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { flashGreen = false }
            } else {
                withAnimation(.easeIn(duration: 0.1)) { flashGreen = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    withAnimation(.easeOut(duration: 0.45)) { flashGreen = false }
                }
            }
        }
    }

    private var rowAccessibilityLabel: String {
        let stateText: String
        switch quest.state {
        case .active:    stateText = "active"
        case .completed: stateText = "claimed"
        case .expired:   stateText = "expired"
        }
        return "\(headline), reward \(quest.goldReward) gold, \(stateText)"
    }

    private var headline: String {
        switch quest.kind {
        case .taskDue:
            return "✓ Complete: \(taskTitle ?? "(missing task)")"
        case .habitDue:
            return "🔄 Log: \(habitTitle ?? "(missing habit)")"
        case .commonFieldTend:
            return "🌼 Tend the common field"
        case .harvestMature:
            return "🌾 Grow \(QuestTuning.harvestMatureThreshold)+ mature plots"
        case .weeklyHarvest:
            return "🌾 Harvest \(quest.progressTarget) mature plots this week"
        }
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch quest.state {
        case .active:
            EmptyView()
        case .completed:
            Text("Claimed")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2), in: Capsule())
                .foregroundStyle(.green)
        case .expired:
            Text("Expired")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2), in: Capsule())
                .foregroundStyle(.gray)
        }
    }
}

private struct WeeklyQuestRow: View {
    let quest: DBModel.Quest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🌾 Harvest \(quest.progressTarget) mature plots this week")
                    .font(.body)
                    .strikethrough(quest.state == .completed)
                Spacer()
                stateBadge
            }
            if quest.state == .active {
                ProgressView(
                    value: Double(quest.progress),
                    total: Double(max(quest.progressTarget, 1))
                )
                .tint(.green)
                Text("\(quest.progress) / \(quest.progressTarget) mature transitions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("🪙 \(quest.goldReward)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            let progress = "Progress: \(quest.progress) of \(quest.progressTarget)"
            let state = quest.state == .completed ? "claimed" : quest.state == .expired ? "expired" : "active"
            return "Weekly harvest quest, \(progress), reward \(quest.goldReward) gold, \(state)"
        }())
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch quest.state {
        case .active:
            EmptyView()
        case .completed:
            Text("Claimed")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2), in: Capsule())
                .foregroundStyle(.green)
        case .expired:
            Text("Expired")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2), in: Capsule())
                .foregroundStyle(.gray)
        }
    }
}

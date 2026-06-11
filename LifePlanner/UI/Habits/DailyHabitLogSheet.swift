import SwiftUI
import SwiftData

/// A habit the back-fill prompt is offering to log, paired with the specific day
/// it was missed. For daily habits that's yesterday; for weekdays-only habits it
/// may be the previous Friday when opened on a Monday.
struct BackfillItem: Identifiable {
    let habit: DBModel.Habit
    let day: Date
    var id: UUID { habit.id }
}

/// Once-per-day prompt shown on first app open, letting the user back-fill the
/// habits they did but forgot to log (e.g. flossing right before bed). Each row
/// records its entry against that habit's own missed day, so streaks stay
/// intact. Items remain after logging (showing a checkmark) so an accidental tap
/// can be undone.
struct DailyHabitLogSheet: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let items: [BackfillItem]

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        row(for: item)
                    }
                } header: {
                    Text("Missed habits")
                } footer: {
                    Text("Did you do any of these? Tap to log them and keep your streak going.")
                }
            }
            .navigationTitle("Catch up on habits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(for item: BackfillItem) -> some View {
        let habit = item.habit
        let done = habit.isDone(on: item.day)
        return Button {
            if !done { HapticPlayer.shared.crescendo() }
            injected.interactors.habits.toggleDone(habit, on: item.day, in: modelContext)
        } label: {
            HStack {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.title)
                        .foregroundStyle(.primary)
                    Text(dayLabel(item.day))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if habit.currentStreak >= 1 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                        Text("\(habit.currentStreak)").fontWeight(.semibold)
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            done
                ? "Undo log: \(habit.title), \(dayLabel(item.day))"
                : "Log habit: \(habit.title), \(dayLabel(item.day))"
        )
    }

    /// "Yesterday" when it was the previous day, otherwise the weekday name
    /// (e.g. "Friday") so the user knows which day they're filling in.
    private func dayLabel(_ day: Date) -> String {
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }
}

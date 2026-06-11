import SwiftUI
import SwiftData

/// Once-per-day prompt shown on first app open, letting the user back-fill the
/// habits they did **yesterday** but forgot to log (e.g. flossing right before
/// bed). Logging here records the entry against `day` (yesterday), so streaks
/// stay intact. Items remain in the list after logging (showing a checkmark) so
/// an accidental tap can be undone.
struct DailyHabitLogSheet: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The day the prompt is back-filling (typically yesterday).
    let day: Date
    /// Habits captured when the sheet was presented. Toggling updates them in
    /// place; the list itself doesn't re-filter so rows don't vanish mid-tap.
    let habits: [DBModel.Habit]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(habits) { habit in
                        Button {
                            let done = habit.isDone(on: day)
                            if !done { HapticPlayer.shared.crescendo() }
                            injected.interactors.habits.toggleDone(habit, on: day, in: modelContext)
                        } label: {
                            HStack {
                                Image(systemName: habit.isDone(on: day) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(habit.isDone(on: day) ? .green : .secondary)
                                Text(habit.title)
                                    .foregroundStyle(.primary)
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
                        .accessibilityLabel(habit.isDone(on: day) ? "Undo log: \(habit.title)" : "Log habit: \(habit.title)")
                    }
                } header: {
                    Text(day.formatted(.dateTime.weekday(.wide)))
                } footer: {
                    Text("Did you do any of these yesterday? Tap to log them and keep your streak going.")
                }
            }
            .navigationTitle("Log yesterday's habits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

import SwiftUI
import SwiftData

/// Month-grid completion history for a single habit. Logged days are filled with
/// the accent colour; today is ringed. Users can page between months.
struct HabitCalendarView: View {

    let habit: DBModel.Habit

    @State private var monthAnchor: Date = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    private var loggedDays: Set<Date> {
        Set((habit.entries ?? []).map { calendar.startOfDay(for: $0.date) })
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            weekdayLabels
            grid
            legend
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous month")

            Spacer()
            Text(monthAnchor, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(isCurrentMonth)
            .accessibilityLabel("Next month")
        }
    }

    private var weekdayLabels: some View {
        HStack {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 36)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isLogged = loggedDays.contains(calendar.startOfDay(for: day))
        let isToday = calendar.isDateInToday(day)
        let dayNumber = calendar.component(.day, from: day)
        return Text("\(dayNumber)")
            .font(.callout)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                Circle()
                    .fill(isLogged ? Color.accentColor : Color.clear)
                    .frame(width: 34, height: 34)
            )
            .overlay(
                Circle()
                    .stroke(isToday ? Color.accentColor : .clear, lineWidth: 1.5)
                    .frame(width: 34, height: 34)
            )
            .foregroundStyle(isLogged ? .white : .primary)
            .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            .accessibilityValue(isLogged ? "completed" : "not completed")
    }

    private var legend: some View {
        HStack(spacing: 16) {
            Label {
                Text("Completed").font(.caption)
            } icon: {
                Circle().fill(Color.accentColor).frame(width: 12, height: 12)
            }
            Label {
                Text("Today").font(.caption)
            } icon: {
                Circle().stroke(Color.accentColor, lineWidth: 1.5).frame(width: 12, height: 12)
            }
            Spacer()
            if habit.currentStreak >= 1 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                    Text("\(habit.currentStreak)").fontWeight(.semibold)
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityLabel("\(habit.currentStreak) day streak")
            }
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Date helpers

    private var isCurrentMonth: Bool {
        calendar.isDate(monthAnchor, equalTo: Date(), toGranularity: .month)
    }

    private func shiftMonth(by delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = next
        }
    }

    /// Weekday symbols rotated so they begin on the calendar's `firstWeekday`.
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// Cells for the month grid: leading nils pad to the first weekday, then one
    /// entry per day of the month.
    private var monthCells: [Date?] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor),
            let range = calendar.range(of: .day, in: .month, for: monthAnchor)
        else { return [] }

        let firstOfMonth = monthInterval.start
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<range.count {
            if let day = calendar.date(byAdding: .day, value: offset, to: firstOfMonth) {
                cells.append(day)
            }
        }
        return cells
    }
}

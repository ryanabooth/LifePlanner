import Foundation
import UserNotifications

/// Lightweight description of a habit that should currently own a reminder.
struct HabitReminderInfo: Sendable {
    let id: UUID
    let title: String
    let time: Date
    /// When true, the reminder fires Monday–Friday only (weekdays cadence).
    var weekdaysOnly: Bool = false
}

protocol NotificationScheduler: Sendable {
    func scheduleHabitReminder(habitID: UUID, title: String, time: Date, weekdaysOnly: Bool) async
    func cancelHabitReminder(habitID: UUID) async
    /// Remove any stale/orphaned habit reminders (deleted, archived, or scheduled
    /// by an older build) and ensure each `active` habit owns exactly one reminder.
    func reconcileHabitReminders(active: [HabitReminderInfo]) async
    func scheduleTaskDue(taskID: UUID, title: String, at fireDate: Date) async
    func cancelTaskDue(taskID: UUID) async
    /// Schedule (or replace) a daily evening nudge to log habits before the day
    /// ends. `cancelEndOfDayReminder` removes it.
    func scheduleEndOfDayReminder(at time: Date) async
    func cancelEndOfDayReminder() async
    /// Schedule (or replace) a next-morning alert for a plot state change.
    func schedulePlotAlert(plotID: UUID, title: String, body: String, fireAt: Date) async
    func cancelPlotAlert(plotID: UUID) async
    /// Fire a one-shot streak-milestone celebration immediately.
    func scheduleStreakMilestone(habitTitle: String, streak: Int, bonus: Int) async
    /// Fire a one-shot achievement-unlock banner immediately.
    func scheduleAchievementUnlocked(emoji: String, title: String) async
}

extension NotificationScheduler {
    func habitReminderID(_ habitID: UUID) -> String { "habit-reminder-\(habitID.uuidString)" }
    /// Gregorian weekday numbers for Mon–Fri (1 = Sunday … 7 = Saturday).
    var weekdayReminderWeekdays: [Int] { [2, 3, 4, 5, 6] }
    /// Per-weekday reminder identifiers for a weekdays-cadence habit.
    func habitReminderWeekdayIDs(_ habitID: UUID) -> [String] {
        weekdayReminderWeekdays.map { "\(habitReminderID(habitID))-wd\($0)" }
    }
    func taskDueID(_ taskID: UUID) -> String { "task-due-\(taskID.uuidString)" }
    func plotAlertID(_ plotID: UUID) -> String { "plot-alert-\(plotID.uuidString)" }
    /// Deliberately not prefixed "habit" so the habit-reminder reconcile pass
    /// doesn't treat it as a stale habit reminder and remove it.
    var endOfDayReminderID: String { "streak-eod-reminder" }
}

final class RealNotificationScheduler: NotificationScheduler {

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func scheduleHabitReminder(habitID: UUID, title: String, time: Date, weekdaysOnly: Bool) async {
        guard UserDefaults.standard.object(forKey: "notif.habitReminders") as? Bool ?? true else { return }
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Time to log this habit."
        content.sound = .default
        content.categoryIdentifier = "habit-reminder"

        // Clear any previously-scheduled variant (daily and per-weekday) first.
        await cancelHabitReminder(habitID: habitID)

        var hm = Calendar.current.dateComponents([.hour, .minute], from: time)

        if weekdaysOnly {
            // One trigger per weekday — a single hour/minute trigger would fire daily.
            for (weekday, id) in zip(weekdayReminderWeekdays, habitReminderWeekdayIDs(habitID)) {
                hm.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: hm, repeats: true)
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                try? await center.add(request)
            }
        } else {
            let trigger = UNCalendarNotificationTrigger(dateMatching: hm, repeats: true)
            let request = UNNotificationRequest(
                identifier: habitReminderID(habitID), content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancelHabitReminder(habitID: UUID) async {
        center.removePendingNotificationRequests(
            withIdentifiers: [habitReminderID(habitID)] + habitReminderWeekdayIDs(habitID))
    }

    func scheduleEndOfDayReminder(at time: Date) async {
        guard UserDefaults.standard.object(forKey: "notif.habitReminders") as? Bool ?? true else { return }
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Keep your streaks alive"
        content.body = "Log today's habits before the day ends."
        content.sound = .default
        content.categoryIdentifier = "habit-reminder"

        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: endOfDayReminderID, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [endOfDayReminderID])
        try? await center.add(request)
    }

    func cancelEndOfDayReminder() async {
        center.removePendingNotificationRequests(withIdentifiers: [endOfDayReminderID])
    }

    func reconcileHabitReminders(active: [HabitReminderInfo]) async {
        var validIDs = Set<String>()
        for habit in active {
            if habit.weekdaysOnly {
                validIDs.formUnion(habitReminderWeekdayIDs(habit.id))
            } else {
                validIDs.insert(habitReminderID(habit.id))
            }
        }
        let pending = await center.pendingNotificationRequests()
        let stale = Self.staleHabitReminderIdentifiers(
            pending: pending.map(\.identifier),
            valid: validIDs
        )
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        for habit in active {
            await scheduleHabitReminder(
                habitID: habit.id, title: habit.title, time: habit.time,
                weekdaysOnly: habit.weekdaysOnly)
        }
    }

    /// Pending habit-reminder identifiers that no longer correspond to a current
    /// habit — orphans from deletions/archives or an older identifier scheme.
    /// Matches the legacy `habit-…` prefix as well as the current `habit-reminder-…`.
    static func staleHabitReminderIdentifiers(pending: [String], valid: Set<String>) -> [String] {
        pending.filter { $0.hasPrefix("habit") && !valid.contains($0) }
    }

    func scheduleTaskDue(taskID: UUID, title: String, at fireDate: Date) async {
        guard fireDate > Date() else { return }
        guard UserDefaults.standard.object(forKey: "notif.taskDue") as? Bool ?? true else { return }
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Task due."
        content.sound = .default
        content.categoryIdentifier = "task-due"

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: taskDueID(taskID),
            content: content,
            trigger: trigger
        )

        center.removePendingNotificationRequests(withIdentifiers: [taskDueID(taskID)])
        do {
            try await center.add(request)
        } catch {
            // Swallow — failure to schedule shouldn't block task save.
        }
    }

    func cancelTaskDue(taskID: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [taskDueID(taskID)])
    }

    func schedulePlotAlert(plotID: UUID, title: String, body: String, fireAt: Date) async {
        guard UserDefaults.standard.object(forKey: "notif.plotAlerts") as? Bool ?? true else { return }
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "plot-alert"

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: plotAlertID(plotID), content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [plotAlertID(plotID)])
        try? await center.add(request)
    }

    func cancelPlotAlert(plotID: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [plotAlertID(plotID)])
        center.removeDeliveredNotifications(withIdentifiers: [plotAlertID(plotID)])
    }

    // Why duplicate streak/achievement notifications can't occur:
    //
    // • scheduleStreakMilestone is called from checkStreakMilestone, which guards
    //   with `milestone > habit.lastStreakMilestone`. The milestone is written back
    //   before the function returns, so a second call for the same streak level is a
    //   no-op. Identifiers use a random UUID so older delivered banners aren't
    //   silently replaced — that is intentional (user may have multiple milestones
    //   queue up if they backfill logs).
    //
    // • scheduleAchievementUnlocked is called from RealAchievementInteractor.checkAll
    //   only when a slug is absent from the persisted Achievement table. checkAll is
    //   idempotent: once the row is inserted, the slug is present on every subsequent
    //   call and the notification branch is skipped. The random-UUID identifier is
    //   similarly intentional — we never want a new achievement to cancel a queued one.
    //
    // • Habit/task reminders (scheduleHabitReminder, scheduleTaskDue) are keyed on
    //   the item's UUID and are removed-then-re-added on every schedule call, so
    //   only one pending request per item can exist at a time. They fire at a future
    //   calendar trigger, not immediately — no overlap with same-action milestone/
    //   achievement banners that fire after a 1-second delay.
    //
    // Investigated 2026-05-18: no code-level duplicate bug found. Any observed
    // duplicate deliveries are device-specific behaviour (e.g. notification centre
    // grouping / re-delivery on relaunch) outside our control.
    func scheduleStreakMilestone(habitTitle: String, streak: Int, bonus: Int) async {
        guard UserDefaults.standard.object(forKey: "notif.streakMilestones") as? Bool ?? true else { return }
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "🔥 \(streak)-day streak!"
        content.body = "\(habitTitle): \(streak) days in a row — you earned 🪙 \(bonus) gold."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "streak-milestone-\(UUID().uuidString)",
            content: content,
            trigger: trigger)
        try? await center.add(request)
    }

    func scheduleAchievementUnlocked(emoji: String, title: String) async {
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(emoji) Achievement Unlocked!"
        content.body = title
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "achievement-\(UUID().uuidString)",
            content: content,
            trigger: trigger)
        try? await center.add(request)
    }

    private func ensureAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }
}

final class StubNotificationScheduler: NotificationScheduler {
    func scheduleHabitReminder(habitID: UUID, title: String, time: Date, weekdaysOnly: Bool) async {}
    func scheduleEndOfDayReminder(at time: Date) async {}
    func cancelEndOfDayReminder() async {}
    func cancelHabitReminder(habitID: UUID) async {}
    func reconcileHabitReminders(active: [HabitReminderInfo]) async {}
    func scheduleTaskDue(taskID: UUID, title: String, at fireDate: Date) async {}
    func cancelTaskDue(taskID: UUID) async {}
    func schedulePlotAlert(plotID: UUID, title: String, body: String, fireAt: Date) async {}
    func cancelPlotAlert(plotID: UUID) async {}
    func scheduleStreakMilestone(habitTitle: String, streak: Int, bonus: Int) async {}
    func scheduleAchievementUnlocked(emoji: String, title: String) async {}
}

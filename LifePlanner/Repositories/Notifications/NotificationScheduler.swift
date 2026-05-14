import Foundation
import UserNotifications

protocol NotificationScheduler: Sendable {
    func scheduleHabitReminder(habitID: UUID, title: String, time: Date) async
    func cancelHabitReminder(habitID: UUID) async
    func scheduleTaskDue(taskID: UUID, title: String, at fireDate: Date) async
    func cancelTaskDue(taskID: UUID) async
    /// Schedule (or replace) a next-morning alert for a plot state change.
    func schedulePlotAlert(plotID: UUID, title: String, body: String, fireAt: Date) async
    func cancelPlotAlert(plotID: UUID) async
    /// Fire a one-shot streak-milestone celebration immediately.
    func scheduleStreakMilestone(habitTitle: String, streak: Int, bonus: Int) async
}

extension NotificationScheduler {
    func habitReminderID(_ habitID: UUID) -> String { "habit-reminder-\(habitID.uuidString)" }
    func taskDueID(_ taskID: UUID) -> String { "task-due-\(taskID.uuidString)" }
    func plotAlertID(_ plotID: UUID) -> String { "plot-alert-\(plotID.uuidString)" }
}

final class RealNotificationScheduler: NotificationScheduler {

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func scheduleHabitReminder(habitID: UUID, title: String, time: Date) async {
        guard UserDefaults.standard.object(forKey: "notif.habitReminders") as? Bool ?? true else { return }
        guard await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Time to log this habit."
        content.sound = .default
        content.categoryIdentifier = "habit-reminder"

        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: habitReminderID(habitID),
            content: content,
            trigger: trigger
        )

        center.removePendingNotificationRequests(withIdentifiers: [habitReminderID(habitID)])
        do {
            try await center.add(request)
        } catch {
            // Swallow — failure to schedule shouldn't block habit save.
        }
    }

    func cancelHabitReminder(habitID: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [habitReminderID(habitID)])
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
    func scheduleHabitReminder(habitID: UUID, title: String, time: Date) async {}
    func cancelHabitReminder(habitID: UUID) async {}
    func scheduleTaskDue(taskID: UUID, title: String, at fireDate: Date) async {}
    func cancelTaskDue(taskID: UUID) async {}
    func schedulePlotAlert(plotID: UUID, title: String, body: String, fireAt: Date) async {}
    func cancelPlotAlert(plotID: UUID) async {}
    func scheduleStreakMilestone(habitTitle: String, streak: Int, bonus: Int) async {}
}

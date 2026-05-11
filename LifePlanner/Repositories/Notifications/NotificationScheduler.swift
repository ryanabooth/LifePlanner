import Foundation
import UserNotifications

protocol NotificationScheduler: Sendable {
    func scheduleHabitReminder(habitID: UUID, title: String, time: Date) async
    func cancelHabitReminder(habitID: UUID) async
    func scheduleTaskDue(taskID: UUID, title: String, at fireDate: Date) async
    func cancelTaskDue(taskID: UUID) async
}

extension NotificationScheduler {
    func habitReminderID(_ habitID: UUID) -> String { "habit-reminder-\(habitID.uuidString)" }
    func taskDueID(_ taskID: UUID) -> String { "task-due-\(taskID.uuidString)" }
}

final class RealNotificationScheduler: NotificationScheduler {

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func scheduleHabitReminder(habitID: UUID, title: String, time: Date) async {
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
}

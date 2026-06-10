import UserNotifications

protocol PushNotificationsHandler { }

final class RealPushNotificationsHandler: NSObject, PushNotificationsHandler {

    private let deepLinksHandler: DeepLinksHandler

    init(deepLinksHandler: DeepLinksHandler) {
        self.deepLinksHandler = deepLinksHandler
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
}

extension RealPushNotificationsHandler: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
        @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.list, .banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        if let deepLink = DeepLink(notificationIdentifier: identifier) {
            let handler = deepLinksHandler
            Task { @MainActor in handler.open(deepLink: deepLink) }
        }
        completionHandler()
    }
}

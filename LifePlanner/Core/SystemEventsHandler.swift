import UIKit
import Combine
import SwiftData

@MainActor
protocol SystemEventsHandler {
    func sceneOpenURLContexts(_ urlContexts: Set<UIOpenURLContext>)
    func sceneDidBecomeActive()
    func sceneWillResignActive()
}

struct RealSystemEventsHandler: SystemEventsHandler {

    let container: DIContainer
    let modelContainer: ModelContainer
    let deepLinksHandler: DeepLinksHandler
    let pushNotificationsHandler: PushNotificationsHandler
    private let cancelBag = CancelBag()

    init(container: DIContainer,
         modelContainer: ModelContainer,
         deepLinksHandler: DeepLinksHandler,
         pushNotificationsHandler: PushNotificationsHandler) {
        self.container = container
        self.modelContainer = modelContainer
        self.deepLinksHandler = deepLinksHandler
        self.pushNotificationsHandler = pushNotificationsHandler
        installKeyboardHeightObserver()
    }

    private func installKeyboardHeightObserver() {
        let appState = container.appState
        NotificationCenter.default.keyboardHeightPublisher
            .sink { [appState] height in
                appState[\.system.keyboardHeight] = height
            }
            .store(in: cancelBag)
    }

    func sceneOpenURLContexts(_ urlContexts: Set<UIOpenURLContext>) {
        guard let url = urlContexts.first?.url, let deepLink = DeepLink(url: url) else { return }
        deepLinksHandler.open(deepLink: deepLink)
    }

    func sceneDidBecomeActive() {
        container.appState[\.system.isActive] = true
        container.interactors.userPermissions.resolveStatus(for: .notifications)
        runDailyTick()
    }

    func sceneWillResignActive() {
        container.appState[\.system.isActive] = false
    }

    /// Foreground daily-tick: applies plot decay for elapsed days, rolls today's
    /// quests if not yet rolled, and expires yesterday's leftovers. Idempotent
    /// across multiple foregrounds on the same calendar day — `FarmInteractor`
    /// guards on `lastDecayTick` and `QuestInteractor.rollDaily` guards on the
    /// day-keyed slot count.
    private func runDailyTick() {
        let context = modelContainer.mainContext
        let now = Date()
        container.interactors.farm.applyDailyDecay(now: now, in: context)
        container.interactors.quests.expireOldQuests(on: now, in: context)
        container.interactors.quests.rollDaily(on: now, in: context)
        container.interactors.quests.rollWeekly(on: now, in: context)
        // If yesterday's batch was rolled before any tasks/habits existed,
        // upgrade commonField placeholders to real candidates now.
        container.interactors.quests.refreshTodaysCommonFieldSlots(in: context)
        if context.hasChanges {
            try? context.save()
        }
        Task.detached { await SpotlightIndexer.shared.reindexAll(in: context) }
    }
}

private extension NotificationCenter {
    var keyboardHeightPublisher: AnyPublisher<CGFloat, Never> {
        let willShow = publisher(for: UIApplication.keyboardWillShowNotification)
            .map { $0.keyboardHeight }
        let willHide = publisher(for: UIApplication.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }
        return Publishers.Merge(willShow, willHide)
            .eraseToAnyPublisher()
    }
}

private extension Notification {
    var keyboardHeight: CGFloat {
        (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?
            .cgRectValue.height ?? 0
    }
}

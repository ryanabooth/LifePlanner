import UIKit
import SwiftData

@MainActor
struct AppEnvironment {
    let isRunningTests: Bool
    let diContainer: DIContainer
    let modelContainer: ModelContainer
    let systemEventsHandler: SystemEventsHandler
}

extension AppEnvironment {

    static func bootstrap() -> AppEnvironment {
        let appState = Store<AppState>(AppState())
        let modelContainer = configuredModelContainer()
        let scheduler = RealNotificationScheduler()
        let interactors = configuredInteractors(appState: appState, scheduler: scheduler)
        // Farm singletons must exist before any UI binds against them. Idempotent.
        interactors.farm.bootstrap(in: modelContainer.mainContext)
        let diContainer = DIContainer(appState: appState, interactors: interactors)
        let deepLinksHandler = RealDeepLinksHandler(container: diContainer)
        let pushNotificationsHandler = RealPushNotificationsHandler(deepLinksHandler: deepLinksHandler)
        let systemEventsHandler = RealSystemEventsHandler(
            container: diContainer,
            modelContainer: modelContainer,
            deepLinksHandler: deepLinksHandler,
            pushNotificationsHandler: pushNotificationsHandler,
            notificationScheduler: scheduler)
        return AppEnvironment(
            isRunningTests: ProcessInfo.processInfo.isRunningTests,
            diContainer: diContainer,
            modelContainer: modelContainer,
            systemEventsHandler: systemEventsHandler)
    }

    private static func configuredModelContainer() -> ModelContainer {
        do {
            return try ModelContainer.appModelContainer()
        } catch {
            return ModelContainer.stub
        }
    }

    private static func configuredInteractors(
        appState: Store<AppState>,
        scheduler: NotificationScheduler
    ) -> DIContainer.Interactors {
        let userPermissions = RealUserPermissionsInteractor(
            appState: appState, openAppSettings: {
                URL(string: UIApplication.openSettingsURLString).flatMap {
                    UIApplication.shared.open($0, options: [:], completionHandler: nil)
                }
            })
        // Economy / Farm / Quests are shared singletons — Habits / Tasks / Goals
        // interactors all reference the same instances so contribution routing
        // and quest auto-claim are consistent across entry points.
        let economy = RealEconomyInteractor()
        let achievementsInteractor = RealAchievementInteractor(scheduler: scheduler)
        let toolsInteractor = RealToolInteractor(economy: economy)
        let farm = RealFarmInteractor(
            economy: economy, scheduler: scheduler,
            achievements: achievementsInteractor, tools: toolsInteractor)
        let quests = RealQuestInteractor(economy: economy)
        let tasks = RealTasksInteractor(
            scheduler: scheduler, farm: farm, quests: quests, achievements: achievementsInteractor)
        let habits = RealHabitsInteractor(
            scheduler: scheduler, economy: economy, farm: farm, quests: quests,
            achievements: achievementsInteractor)
        let goals = RealGoalsInteractor(farm: farm)
        let cosmetics = RealCosmeticInteractor(
            economy: economy, achievements: achievementsInteractor)
        let weather = RealWeatherInteractor(economy: economy, farm: farm)
        return .init(
            userPermissions: userPermissions,
            tasks: tasks,
            habits: habits,
            goals: goals,
            economy: economy,
            farm: farm,
            quests: quests,
            cosmetics: cosmetics,
            weather: weather,
            achievements: achievementsInteractor,
            tools: toolsInteractor
        )
    }
}

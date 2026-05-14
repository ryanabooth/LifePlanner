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
        let interactors = configuredInteractors(appState: appState)
        // Farm singletons must exist before any UI binds against them. Idempotent.
        interactors.farm.bootstrap(in: modelContainer.mainContext)
        let diContainer = DIContainer(appState: appState, interactors: interactors)
        let deepLinksHandler = RealDeepLinksHandler(container: diContainer)
        let pushNotificationsHandler = RealPushNotificationsHandler(deepLinksHandler: deepLinksHandler)
        let systemEventsHandler = RealSystemEventsHandler(
            container: diContainer,
            deepLinksHandler: deepLinksHandler,
            pushNotificationsHandler: pushNotificationsHandler)
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
        appState: Store<AppState>
    ) -> DIContainer.Interactors {
        let userPermissions = RealUserPermissionsInteractor(
            appState: appState, openAppSettings: {
                URL(string: UIApplication.openSettingsURLString).flatMap {
                    UIApplication.shared.open($0, options: [:], completionHandler: nil)
                }
            })
        // Economy and Farm are shared singletons — Habits / Tasks / Goals interactors
        // all reference the same Farm instance so contribution routing is consistent.
        let economy = RealEconomyInteractor()
        let farm = RealFarmInteractor(economy: economy)
        let tasks = RealTasksInteractor(farm: farm)
        let habits = RealHabitsInteractor(farm: farm)
        let goals = RealGoalsInteractor(farm: farm)
        return .init(
            userPermissions: userPermissions,
            tasks: tasks,
            habits: habits,
            goals: goals,
            economy: economy,
            farm: farm
        )
    }
}

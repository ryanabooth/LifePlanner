import SwiftUI
import SwiftData

struct DIContainer {

    let appState: Store<AppState>
    let interactors: Interactors

    init(appState: Store<AppState> = .init(AppState()), interactors: Interactors) {
        self.appState = appState
        self.interactors = interactors
    }

    init(appState: AppState, interactors: Interactors) {
        self.init(appState: Store<AppState>(appState), interactors: interactors)
    }
}

extension DIContainer {
    struct Interactors {
        let userPermissions: UserPermissionsInteractor
        let tasks: TasksInteractor
        let habits: HabitsInteractor
        let goals: GoalsInteractor
        let economy: EconomyInteractor
        let farm: FarmInteractor
        let quests: QuestInteractor
        let cosmetics: CosmeticInteractor

        static var stub: Self {
            .init(
                userPermissions: StubUserPermissionsInteractor(),
                tasks: StubTasksInteractor(),
                habits: StubHabitsInteractor(),
                goals: StubGoalsInteractor(),
                economy: StubEconomyInteractor(),
                farm: StubFarmInteractor(),
                quests: StubQuestInteractor(),
                cosmetics: StubCosmeticInteractor()
            )
        }
    }
}

extension EnvironmentValues {
    @Entry var injected: DIContainer = DIContainer(appState: AppState(), interactors: .stub)
}

extension View {
    func inject(_ container: DIContainer) -> some View {
        environment(\.injected, container)
    }
}

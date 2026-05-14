import SwiftUI

enum MainTab: Hashable {
    case farm
    case tasks
    case habits
    case goals
}

struct MainTabView: View {

    @Environment(\.injected) private var injected: DIContainer
    @State private var selection: MainTab = .farm

    var body: some View {
        TabView(selection: $selection) {
            FarmTabView()
                .tabItem { Label("Farm", systemImage: "leaf") }
                .tag(MainTab.farm)

            TasksTabView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(MainTab.tasks)

            HabitsTabView()
                .tabItem { Label("Habits", systemImage: "repeat") }
                .tag(MainTab.habits)

            GoalsTabView()
                .tabItem { Label("Goals", systemImage: "target") }
                .tag(MainTab.goals)
        }
    }
}

#Preview {
    MainTabView()
}

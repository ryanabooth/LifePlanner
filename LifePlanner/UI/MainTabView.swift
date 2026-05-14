import SwiftUI

enum MainTab: Hashable {
    case tasks
    case habits
    case goals
}

struct MainTabView: View {

    @Environment(\.injected) private var injected: DIContainer
    @State private var selection: MainTab = .tasks

    var body: some View {
        TabView(selection: $selection) {
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

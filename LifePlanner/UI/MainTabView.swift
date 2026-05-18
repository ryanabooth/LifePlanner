import SwiftUI
import SwiftData

enum MainTab: Hashable {
    case farm
    case tasks
    case habits
    case goals
    case settings
}

struct MainTabView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var selection: MainTab

    @State private var selectedTab: MainTab? = .farm

    @Query private var allQuests: [DBModel.Quest]

    private var activeQuestCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        return allQuests.filter { $0.day >= today && $0.day < tomorrow && $0.state == .active }.count
    }

    init(selection: Binding<MainTab> = .constant(.farm)) {
        _selection = selection
    }

    var body: some View {
        if sizeClass == .compact {
            compactTabView
        } else {
            regularSplitView
        }
    }

    // MARK: - Compact (iPhone)

    private var compactTabView: some View {
        TabView(selection: $selection) {
            FarmTabView()
                .tabItem { Label("Farm", systemImage: "leaf") }
                .tag(MainTab.farm)
                .badge(activeQuestCount)

            TasksTabView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(MainTab.tasks)

            HabitsTabView()
                .tabItem { Label("Habits", systemImage: "repeat") }
                .tag(MainTab.habits)

            GoalsTabView()
                .tabItem { Label("Goals", systemImage: "target") }
                .tag(MainTab.goals)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
    }

    // MARK: - Regular (iPad)

    private var regularSplitView: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: MainTab.farm)     { Label("Farm",     systemImage: "leaf") }
                    .badge(activeQuestCount)
                NavigationLink(value: MainTab.tasks)    { Label("Tasks",    systemImage: "checklist") }
                NavigationLink(value: MainTab.habits)   { Label("Habits",   systemImage: "repeat") }
                NavigationLink(value: MainTab.goals)    { Label("Goals",    systemImage: "target") }
                NavigationLink(value: MainTab.settings) { Label("Settings", systemImage: "gearshape") }
            }
            .navigationTitle("Tiller")
        } detail: {
            switch selectedTab {
            case .farm:     FarmTabView()
            case .tasks:    TasksTabView()
            case .habits:   HabitsTabView()
            case .goals:    GoalsTabView()
            case .settings: SettingsView()
            case nil:       FarmTabView()
            }
        }
    }
}

#Preview {
    MainTabView()
}

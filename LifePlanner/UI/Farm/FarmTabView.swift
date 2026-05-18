import SwiftUI
import SwiftData
import SpriteKit
import Combine

private enum FarmDestination: Hashable {
    case plotDetail(UUID)
    case questLog
    case capacityUpgrade
    case cosmeticShop
    case workshop
}

/// SwiftUI host for the SpriteKit farm scene. Watches `FarmPlot` and
/// `FarmState` with `@Query`; pushes snapshots into the scene whenever the
/// reactive results change. Hosts the SwiftUI overlay buttons + nav
/// destinations on top of the scene.
struct FarmTabView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext

    @Query private var plots: [DBModel.FarmPlot]
    @Query private var farmStates: [DBModel.FarmState]
    @Query private var ownedCosmetics: [DBModel.OwnedCosmetic]
    @Query private var allQuests: [DBModel.Quest]

    private var activeQuestCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        return allQuests.filter { $0.day >= today && $0.day < tomorrow && $0.state == .active }.count
    }

    /// Persisted across re-renders so SpriteView doesn't reset every body
    /// evaluation. Size is provisional — the scene uses `.resizeFill` so it
    /// adopts the real view bounds once `SpriteView` lays it out.
    @State private var scene: FarmScene = {
        let s = FarmScene(size: CGSize(width: 400, height: 800))
        s.scaleMode = .resizeFill
        return s
    }()

    @State private var navigationPath: [FarmDestination] = []
    @State private var showAddMenu = false
    @State private var showWeatherExplainer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var weatherEvents: [DBModel.WeatherEvent]

    private var activeWeather: DBModel.WeatherEvent? {
        let now = Date()
        return weatherEvents.first { $0.startedAt <= now && $0.expiresAt > now }
    }
    @State private var showAddTask = false
    @State private var showAddHabit = false
    @State private var showAddGoal = false
    @State private var showDevMenu = false

    private var currentSeason: Season { Season.current() }

    var body: some View {
        NavigationStack(path: $navigationPath) {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
                    .onAppear {
                        scene.topSafeAreaInset    = proxy.safeAreaInsets.top + 12
                        scene.bottomSafeAreaInset = proxy.safeAreaInsets.bottom + 20
                        scene.applySeason(currentSeason, reduceMotion: reduceMotion)
                        pushSnapshot()
                        pushCosmeticSnapshot()
                    }
                    .onChange(of: snapshotSignature) { _, _ in pushSnapshot() }
                    .onChange(of: cosmeticSignature) { _, _ in pushCosmeticSnapshot() }
                    .onChange(of: proxy.safeAreaInsets.top) { _, newInset in
                        scene.topSafeAreaInset = newInset + 12
                    }
                    .onChange(of: proxy.safeAreaInsets.bottom) { _, newInset in
                        scene.bottomSafeAreaInset = newInset + 20
                    }
                    .onReceive(scene.tappedPlotID) { id in
                        navigationPath.append(.plotDetail(id))
                    }
                    .onReceive(scene.tappedFarmhouse) { _ in
                        showDevMenu = true
                    }

                overlayButtons
                    .padding(.trailing, 16)
                    .padding(.top, proxy.safeAreaInsets.top + 48)

                VStack(alignment: .leading, spacing: 6) {
                    WeatherHUDPill(event: activeWeather, onTap: { showWeatherExplainer = true })
                    SeasonHUDPill(season: currentSeason)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 16)
                .padding(.top, proxy.safeAreaInsets.top + 48)
            }
            .overlay(alignment: .bottomTrailing) {
                addFAB
                    .padding(.trailing, 20)
                    .padding(.bottom, 8)
            }
        }
        .navigationDestination(for: FarmDestination.self) { destination in
            switch destination {
            case .plotDetail(let id):   PlotDetailView(plotID: id)
            case .questLog:             QuestLogView()
            case .capacityUpgrade:      CapacityUpgradeSheet()
            case .cosmeticShop:         CosmeticShopView()
            case .workshop:             WorkshopView()
            }
        }
        } // NavigationStack
        .sheet(isPresented: $showAddTask) {
            AddTaskSheet { draft in
                injected.interactors.tasks.add(draft, in: modelContext)
            }
        }
        .sheet(isPresented: $showAddHabit) {
            AddHabitSheet { draft in
                injected.interactors.habits.add(draft, in: modelContext)
            }
        }
        .sheet(isPresented: $showAddGoal) {
            AddGoalSheet { draft in
                injected.interactors.goals.add(draft, in: modelContext)
            }
        }
        .sheet(isPresented: $showDevMenu) {
            DevMenuView()
        }
        .sheet(isPresented: $showWeatherExplainer) {
            WeatherExplainerSheet(event: activeWeather)
        }
    }

    private var overlayButtons: some View {
        VStack(spacing: 10) {
            Button {
                HapticPlayer.shared.tap()
                navigationPath.append(.questLog)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "scroll")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background(.thinMaterial, in: Circle())
                    if activeQuestCount > 0 {
                        Text("\(activeQuestCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.red, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .accessibilityLabel(activeQuestCount > 0 ? "Quest Log, \(activeQuestCount) active" : "Quest Log")

            Button {
                HapticPlayer.shared.tap()
                navigationPath.append(.capacityUpgrade)
            } label: {
                Image(systemName: "plus.square.dashed")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Expand Farm")

            Button {
                HapticPlayer.shared.tap()
                navigationPath.append(.cosmeticShop)
            } label: {
                Image(systemName: "tshirt")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Cosmetic Shop")

            Button {
                HapticPlayer.shared.tap()
                navigationPath.append(.workshop)
            } label: {
                Image(systemName: "hammer")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Workshop")
        }
        .foregroundStyle(.primary)
    }

    private var addFAB: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if showAddMenu {
                fabSubButton(label: "New Goal", icon: "target") {
                    showAddGoal = true
                }
                fabSubButton(label: "New Habit", icon: "arrow.trianglehead.2.clockwise") {
                    showAddHabit = true
                }
                fabSubButton(label: "New Task", icon: "checkmark.circle") {
                    showAddTask = true
                }
            }

            Button {
                HapticPlayer.shared.tap()
                withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
                    showAddMenu.toggle()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .rotationEffect(.degrees(showAddMenu ? 45 : 0))
                    .frame(width: 56, height: 56)
                    .background(.tint, in: Circle())
                    .foregroundStyle(.white)
                    .shadow(radius: 4, y: 2)
            }
            .accessibilityLabel(showAddMenu ? "Close menu" : "Add task, habit, or goal")
        }
    }

    private func fabSubButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.2)) { showAddMenu = false }
            action()
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())
            }
        }
        .foregroundStyle(.primary)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Signature that changes whenever any rendered property changes — plot
    /// identity, health, state, kind, or the gold balance. SwiftUI's onChange
    /// only fires when the integer differs, so this is cheaper than diffing
    /// every plot row by hand.
    private var snapshotSignature: Int {
        var hasher = Hasher()
        hasher.combine(plots.count)
        for plot in plots {
            hasher.combine(plot.id)
            hasher.combine(plot.health)
            hasher.combine(plot.state.rawValue)
            hasher.combine(plot.kind.rawValue)
            hasher.combine(plot.gridX)
        }
        hasher.combine(farmStates.first?.gold ?? 0)
        hasher.combine(farmStates.first?.plotCapacity ?? 0)
        return hasher.finalize()
    }

    private func pushSnapshot() {
        scene.snapshot(
            plots: plots,
            gold: farmStates.first?.gold ?? 0,
            capacity: farmStates.first?.plotCapacity ?? 0
        )
    }

    /// Stable key that changes whenever the equipped set changes — drives
    /// `onChange` without diffing individual rows.
    private var cosmeticSignature: String {
        CosmeticKind.allCases
            .compactMap { kind in ownedCosmetics.first { $0.kind == kind && $0.equippedAt != nil }?.slug }
            .joined(separator: "-")
    }

    private func pushCosmeticSnapshot() {
        func equipped(_ kind: CosmeticKind) -> String? {
            ownedCosmetics.first { $0.kind == kind && $0.equippedAt != nil }?.slug
        }
        scene.snapshotCosmetics(
            equippedHatSlug:    equipped(.hat),
            equippedOutfitSlug: equipped(.outfit),
            equippedPetSlug:    equipped(.pet),
            equippedDecorSlug:  equipped(.farmhouseDecor)
        )
    }
}

#Preview {
    FarmTabView()
        .modelContainer(for: [
            DBModel.FarmState.self, DBModel.FarmPlot.self, DBModel.Goal.self,
            DBModel.Task.self, DBModel.Habit.self, DBModel.HabitLogEntry.self,
            DBModel.Quest.self, DBModel.OwnedCosmetic.self
        ], inMemory: true)
}

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {

    @AppStorage("notif.habitReminders")   private var habitReminders   = true
    @AppStorage("notif.taskDue")          private var taskDue           = true
    @AppStorage("notif.plotAlerts")       private var plotAlerts        = true
    @AppStorage("notif.streakMilestones") private var streakMilestones  = true
    @AppStorage("notif.endOfDayReminder") private var endOfDayReminder  = false
    @AppStorage("notif.endOfDayReminderTime") private var endOfDayReminderTime = Self.defaultEndOfDayTime
    @AppStorage("farm.vacationMode")      private var vacationMode      = false

    /// 8:00 PM, stored as seconds since reference date so it fits in @AppStorage.
    private static var defaultEndOfDayTime: Double {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 20
        comps.minute = 0
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.timeIntervalSinceReferenceDate
    }

    private var endOfDayDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: endOfDayReminderTime) },
            set: { endOfDayReminderTime = $0.timeIntervalSinceReferenceDate }
        )
    }

    @Environment(\.injected) private var injected
    @Environment(\.modelContext) private var modelContext

    @Query private var tasks:  [DBModel.Task]
    @Query private var habits: [DBModel.Habit]
    @Query private var goals:  [DBModel.Goal]

    @State private var exportURL: URL?
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                insightsSection
                notificationsSection
                farmSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .onAppear { exportURL = buildExportURL() }
            .onChange(of: tasks.count)  { _, _ in exportURL = buildExportURL() }
            .onChange(of: habits.count) { _, _ in exportURL = buildExportURL() }
            .onChange(of: goals.count)  { _, _ in exportURL = buildExportURL() }
            .confirmationDialog(
                "Reset Farm?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset Farm", role: .destructive) { resetFarm() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All farm plots and state will be removed. Tasks, habits, and goals are kept.")
            }
        }
    }

    // MARK: - Sections

    private var insightsSection: some View {
        Section {
            NavigationLink(destination: StatsView()) {
                Label("View insights", systemImage: "chart.xyaxis.line")
            }
            NavigationLink(destination: TrophyShelfView()) {
                Label("Trophy shelf", systemImage: "trophy")
            }
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle("Habit reminders",   isOn: $habitReminders)
            Toggle("Task due alerts",   isOn: $taskDue)
            Toggle("Farm plot alerts",  isOn: $plotAlerts)
            Toggle("Streak milestones", isOn: $streakMilestones)
            Toggle("End-of-day streak reminder", isOn: $endOfDayReminder)
            if endOfDayReminder {
                DatePicker("Remind me at", selection: endOfDayDate, displayedComponents: [.hourAndMinute])
            }
            Button("Open notification settings…") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            if endOfDayReminder {
                Text("A daily nudge to log your habits before the day ends and a streak breaks.")
            }
        }
        .onChange(of: endOfDayReminder) { _, on in
            injected.interactors.habits.setEndOfDayReminder(
                enabled: on, time: endOfDayDate.wrappedValue)
        }
        .onChange(of: endOfDayReminderTime) { _, _ in
            if endOfDayReminder {
                injected.interactors.habits.setEndOfDayReminder(
                    enabled: true, time: endOfDayDate.wrappedValue)
            }
        }
    }

    private var farmSection: some View {
        Section {
            Toggle(isOn: $vacationMode) {
                Label("Vacation mode", systemImage: "figure.walk.departure")
            }
        } header: {
            Text("Farm")
        } footer: {
            Text("Pauses plot health decay while you're away. Days skipped won't count against your plots when you return.")
        }
    }

    private var dataSection: some View {
        Section("Data") {
            if let url = exportURL {
                ShareLink(
                    item: url,
                    preview: SharePreview("tiller-data.json", image: Image(systemName: "doc.text"))
                ) {
                    Label("Export data (JSON)", systemImage: "square.and.arrow.up")
                }
            } else {
                Label("Export data (JSON)", systemImage: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
            Button("Reset farm", role: .destructive) {
                showResetConfirm = true
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "Tiller")
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: buildNumber)
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private func buildExportURL() -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let payload = ExportPayload(
            exportedAt: Date(),
            tasks: tasks.map(TaskExport.init),
            habits: habits.map(HabitExport.init),
            goals: goals.map(GoalExport.init)
        )
        guard let data = try? encoder.encode(payload) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tiller-data.json")
        try? data.write(to: url)
        return url
    }

    private func resetFarm() {
        try? modelContext.delete(model: DBModel.FarmPlot.self)
        try? modelContext.delete(model: DBModel.FarmState.self)
        modelContext.saveQuietly()
        injected.interactors.farm.bootstrap(in: modelContext)
    }
}

// MARK: - Export DTOs

private struct ExportPayload: Encodable {
    let exportedAt: Date
    let tasks:  [TaskExport]
    let habits: [HabitExport]
    let goals:  [GoalExport]
}

private struct TaskExport: Encodable {
    let id: UUID
    let title: String
    let notes: String?
    let dueDate: Date?
    let priority: String
    let isDone: Bool
    let completedAt: Date?
    let recurrence: String?
    let linkedGoalID: UUID?
    let linkedGoalTitle: String?
    let createdAt: Date

    init(_ task: DBModel.Task) {
        id              = task.id
        title           = task.title
        notes           = task.notes
        dueDate         = task.dueDate
        priority        = task.priority.label
        isDone          = task.isDone
        completedAt     = task.completedAt
        recurrence      = task.recurrence?.label
        linkedGoalID    = task.goals?.first?.id
        linkedGoalTitle = task.goals?.first?.title
        createdAt       = task.createdAt
    }
}

private struct HabitExport: Encodable {
    let id: UUID
    let title: String
    let notes: String?
    let frequency: String
    let currentStreak: Int
    let longestStreak: Int
    let archived: Bool
    let linkedGoalID: UUID?
    let linkedGoalTitle: String?
    let createdAt: Date

    init(_ habit: DBModel.Habit) {
        id              = habit.id
        title           = habit.title
        notes           = habit.notes
        frequency       = habit.frequency.label
        currentStreak   = habit.currentStreak
        longestStreak   = habit.longestStreak
        archived        = habit.archived
        linkedGoalID    = habit.goals?.first?.id
        linkedGoalTitle = habit.goals?.first?.title
        createdAt       = habit.createdAt
    }
}

private struct GoalExport: Encodable {
    let id: UUID
    let title: String
    let why: String?
    let targetDate: Date?
    let status: String
    let metricUnit: String?
    let metricTarget: Double
    let metricValue: Double
    let createdAt: Date

    init(_ goal: DBModel.Goal) {
        id           = goal.id
        title        = goal.title
        why          = goal.why
        targetDate   = goal.targetDate
        status       = goal.status.label
        metricUnit   = goal.metricUnit
        metricTarget = goal.metricTarget
        metricValue  = goal.metricValue
        createdAt    = goal.createdAt
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [DBModel.Task.self, DBModel.Habit.self, DBModel.Goal.self], inMemory: true)
}

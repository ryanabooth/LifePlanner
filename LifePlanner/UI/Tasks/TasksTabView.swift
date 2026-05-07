import SwiftUI

struct TasksTabView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Tasks", systemImage: "checklist", description: Text("Coming soon."))
                .navigationTitle("Tasks")
        }
    }
}

#Preview {
    TasksTabView()
}

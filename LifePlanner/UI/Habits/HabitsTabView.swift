import SwiftUI

struct HabitsTabView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Habits", systemImage: "repeat", description: Text("Coming soon."))
                .navigationTitle("Habits")
        }
    }
}

#Preview {
    HabitsTabView()
}

import SwiftUI

struct GoalsTabView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Goals", systemImage: "target", description: Text("Coming soon."))
                .navigationTitle("Goals")
        }
    }
}

#Preview {
    GoalsTabView()
}

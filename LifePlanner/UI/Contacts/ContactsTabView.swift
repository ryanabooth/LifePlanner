import SwiftUI

struct ContactsTabView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Contacts", systemImage: "person.2", description: Text("Coming soon."))
                .navigationTitle("Contacts")
        }
    }
}

#Preview {
    ContactsTabView()
}

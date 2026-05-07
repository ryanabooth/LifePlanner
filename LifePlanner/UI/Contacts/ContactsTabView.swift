import SwiftUI
import SwiftData
import Contacts

struct ContactsTabView: View {

    @Environment(\.injected) private var injected: DIContainer

    @State private var status: CNAuthorizationStatus = .notDetermined
    @State private var contacts: [SystemContact] = []
    @State private var loadError: String?
    @State private var query = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Contacts")
        }
        .task { await refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .authorized, .limited:
            if let loadError {
                ContentUnavailableView(
                    "Couldn't load contacts",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if contacts.isEmpty {
                ContentUnavailableView(
                    "No contacts found",
                    systemImage: "person.2",
                    description: Text("Your address book appears to be empty.")
                )
            } else {
                contactList
            }
        case .denied, .restricted:
            ContentUnavailableView {
                Label("Access denied", systemImage: "lock")
            } description: {
                Text("Enable Contacts access in Settings to use this feature.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .notDetermined:
            ContentUnavailableView {
                Label("Connect your contacts", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("LifePlanner reads your address book so you can add private notes and tags to people. Nothing leaves your device.")
            } actions: {
                Button("Grant Access") {
                    Task { await requestAccess() }
                }
                .buttonStyle(.borderedProminent)
            }
        @unknown default:
            EmptyView()
        }
    }

    private var contactList: some View {
        List {
            ForEach(filtered) { contact in
                NavigationLink {
                    ContactDetailView(systemContact: contact)
                } label: {
                    ContactRow(contact: contact)
                }
            }
        }
        .searchable(text: $query, prompt: "Search contacts")
        .refreshable { await refresh() }
    }

    private var filtered: [SystemContact] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return contacts }
        return contacts.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    private func refresh() async {
        status = injected.interactors.contactsBridge.authorizationStatus()
        guard status == .authorized || status == .limited else { return }
        do {
            contacts = try await injected.interactors.contactsBridge.fetchAll()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func requestAccess() async {
        do {
            _ = try await injected.interactors.contactsBridge.requestAccess()
        } catch {
            loadError = error.localizedDescription
        }
        await refresh()
    }
}

private struct ContactRow: View {
    let contact: SystemContact

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.15))
                Text(initials)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading) {
                Text(contact.displayName)
                if let phone = contact.phones.first?.value {
                    Text(phone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let email = contact.emails.first?.value {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var initials: String {
        let parts = contact.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        return parts.map(String.init).joined().uppercased()
    }
}

#Preview {
    ContactsTabView()
        .modelContainer(for: DBModel.Contact.self, inMemory: true)
}

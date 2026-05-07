import SwiftUI
import SwiftData

struct ContactDetailView: View {

    @Environment(\.injected) private var injected: DIContainer
    @Environment(\.modelContext) private var modelContext

    let systemContact: SystemContact

    @Query private var enrichments: [DBModel.Contact]

    @State private var notesDraft: String = ""
    @State private var tagsField: String = ""
    @State private var dirty = false

    init(systemContact: SystemContact) {
        self.systemContact = systemContact
        let id = systemContact.id
        _enrichments = Query(
            filter: #Predicate<DBModel.Contact> { $0.systemIdentifier == id },
            sort: [SortDescriptor(\DBModel.Contact.updatedAt, order: .reverse)]
        )
    }

    private var existing: DBModel.Contact? { enrichments.first }

    var body: some View {
        Form {
            Section {
                ForEach(systemContact.phones, id: \.self) { item in
                    LabeledContent(item.label.isEmpty ? "Phone" : item.label, value: item.value)
                }
                ForEach(systemContact.emails, id: \.self) { item in
                    LabeledContent(item.label.isEmpty ? "Email" : item.label, value: item.value)
                }
                if !systemContact.organization.isEmpty {
                    LabeledContent("Organization", value: systemContact.organization)
                }
            } header: {
                Text("System")
            } footer: {
                Text("Read from your iOS Contacts. Edit there to update.")
            }

            Section("Notes") {
                TextField("Private notes (only in LifePlanner)", text: $notesDraft, axis: .vertical)
                    .lineLimit(3...8)
                    .onChange(of: notesDraft) { _, _ in dirty = true }
            }

            Section {
                TextField("Comma-separated tags", text: $tagsField)
                    .textInputAutocapitalization(.never)
                    .onChange(of: tagsField) { _, _ in dirty = true }
                if !currentTags.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], alignment: .leading) {
                        ForEach(currentTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.tint.opacity(0.15), in: Capsule())
                        }
                    }
                }
            } header: {
                Text("Tags")
            }

            Section {
                Button("Mark interaction now") {
                    injected.interactors.contacts.recordInteraction(
                        systemID: systemContact.id,
                        displayName: systemContact.displayName,
                        at: Date(),
                        in: modelContext
                    )
                }
                if let last = existing?.lastInteraction {
                    LabeledContent("Last interaction", value: last.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if let existing, existing.hasEnrichment {
                Section {
                    Button("Clear LifePlanner data for this contact", role: .destructive) {
                        injected.interactors.contacts.deleteEnrichment(existing, in: modelContext)
                        notesDraft = ""
                        tagsField = ""
                        dirty = false
                    }
                }
            }
        }
        .navigationTitle(systemContact.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { save() }
                    .disabled(!dirty)
            }
        }
        .onAppear { hydrate() }
        .onChange(of: existing?.id) { _, _ in hydrate() }
    }

    private var currentTags: [String] {
        tagsField
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func hydrate() {
        notesDraft = existing?.notes ?? ""
        tagsField = (existing?.tags ?? []).joined(separator: ", ")
        dirty = false
    }

    private func save() {
        let draft = ContactEnrichmentDraft(
            notes: notesDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: currentTags
        )
        _ = injected.interactors.contacts.upsertEnrichment(
            systemID: systemContact.id,
            displayName: systemContact.displayName,
            draft: draft,
            in: modelContext
        )
        dirty = false
    }
}

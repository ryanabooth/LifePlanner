import Foundation
import Contacts

protocol ContactsBridge: Sendable {
    func authorizationStatus() -> CNAuthorizationStatus
    func requestAccess() async throws -> Bool
    func fetchAll() async throws -> [SystemContact]
    func fetch(identifier: String) async throws -> SystemContact?
}

final class RealContactsBridge: ContactsBridge {

    private let store = CNContactStore()

    private static let keys: [CNKeyDescriptor] = [
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactOrganizationNameKey,
        CNContactPhoneNumbersKey,
        CNContactEmailAddressesKey,
        CNContactBirthdayKey
    ].map { $0 as CNKeyDescriptor }

    func authorizationStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    func fetchAll() async throws -> [SystemContact] {
        let request = CNContactFetchRequest(keysToFetch: Self.keys)
        request.sortOrder = .userDefault
        var results: [SystemContact] = []
        try store.enumerateContacts(with: request) { contact, _ in
            results.append(Self.makeSystemContact(from: contact))
        }
        return results
    }

    func fetch(identifier: String) async throws -> SystemContact? {
        do {
            let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: Self.keys)
            return Self.makeSystemContact(from: contact)
        } catch {
            return nil
        }
    }

    private static func makeSystemContact(from contact: CNContact) -> SystemContact {
        SystemContact(
            id: contact.identifier,
            givenName: contact.givenName,
            familyName: contact.familyName,
            organization: contact.organizationName,
            phones: contact.phoneNumbers.map {
                SystemContact.LabeledValue(
                    label: humanLabel($0.label),
                    value: $0.value.stringValue
                )
            },
            emails: contact.emailAddresses.map {
                SystemContact.LabeledValue(
                    label: humanLabel($0.label),
                    value: $0.value as String
                )
            },
            birthday: contact.birthday
        )
    }

    private static func humanLabel(_ raw: String?) -> String {
        guard let raw else { return "" }
        return CNLabeledValue<NSString>.localizedString(forLabel: raw)
    }
}

final class StubContactsBridge: ContactsBridge {
    func authorizationStatus() -> CNAuthorizationStatus { .notDetermined }
    func requestAccess() async throws -> Bool { false }
    func fetchAll() async throws -> [SystemContact] { [] }
    func fetch(identifier: String) async throws -> SystemContact? { nil }
}

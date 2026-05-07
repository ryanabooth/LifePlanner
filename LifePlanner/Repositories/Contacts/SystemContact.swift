import Foundation

struct SystemContact: Identifiable, Hashable, Sendable {
    let id: String
    var givenName: String
    var familyName: String
    var organization: String
    var phones: [LabeledValue]
    var emails: [LabeledValue]
    var birthday: DateComponents?

    var displayName: String {
        let combined = "\(givenName) \(familyName)".trimmingCharacters(in: .whitespaces)
        if !combined.isEmpty { return combined }
        if !organization.isEmpty { return organization }
        return phones.first?.value ?? emails.first?.value ?? "Unnamed"
    }

    struct LabeledValue: Hashable, Sendable {
        var label: String
        var value: String
    }
}

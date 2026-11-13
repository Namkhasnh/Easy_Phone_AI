import Foundation

/// One contact found for a spoken / typed name (ARCHITECTURE §4.2, spec §6.6). 🔒 `id` never leaves the device (D-056).
// TODO(spec): ARCHITECTURE §4.2 names `ContactMatch` / `PhoneEntry` without fields; these are what S06 (1C.9) shows:
// name, photo, how many numbers.
struct ContactMatch: Sendable, Hashable, Identifiable {
    /// `CNContact.identifier`.
    let id: String
    var displayName: String
    var thumbnail: Data?
    var phoneCount: Int
    /// Found through a saved nickname ("mẹ" → this contact), §7.2 steps 1–2.
    var viaNickname: Bool = false
}

/// One phone number of a contact. 🔒 `number` is device-only (D-056); masking + E.164 come with 1C.8.
struct PhoneEntry: Sendable, Hashable {
    /// iOS label already localized ("di động", "nhà"…), nil when the number has none.
    var label: String?
    var number: String
}

/// The fields `ContactMatcher` needs from a device contact (built by the live service, or by tests).
struct ContactRecord: Sendable, Hashable {
    let id: String
    var givenName: String
    var middleName: String = ""
    var familyName: String
    var thumbnail: Data?
    var phoneCount: Int

    /// "Họ Đệm Tên" as Vietnamese write it; falls back to whatever part exists.
    var displayName: String {
        [familyName, middleName, givenName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var match: ContactMatch {
        ContactMatch(id: id, displayName: displayName, thumbnail: thumbnail, phoneCount: phoneCount)
    }
}

/// Device contacts (ARCHITECTURE §4.2). Runs on device only (spec §6.6 AC1); the list is never uploaded (D-056).
/// Not usable access → `ServiceError.permissionDenied(.contacts)`; `limited` searches the allowed subset.
protocol ContactsService: Sendable {
    /// DATA_MODEL §7.2 order: exact nickname → normalized nickname → given / family / full name contains → none.
    /// Several results are all returned: the caller shows a picker (D-106).
    func match(name: String) async throws -> [ContactMatch]
    func phoneNumbers(contactId: String) async throws -> [PhoneEntry]
    /// The S04 contact row (name, photo) for a stored `contactId`; nil when it was deleted or is not shared (limited).
    // TODO(spec): not in ARCHITECTURE §4.2; S04 must show the contact name for the 🔒 `contactId` (UI_SCREENS S04).
    func contact(id: String) async throws -> ContactMatch?
}

/// Pure DATA_MODEL §7.2 matching (unit-tested; the live and mock services both use it).
enum ContactMatcher {
    /// - Parameters:
    ///   - nicknameContactId: the contact of a saved nickname for `name` (exact or normalized, looked up by the caller
    ///     in `LocalDataRepository`), nil when there is none.
    static func match(_ name: String, nicknameContactId: String?, in contacts: [ContactRecord]) -> [ContactMatch] {
        if let id = nicknameContactId, let hit = contacts.first(where: { $0.id == id }) {
            var m = hit.match
            m.viaNickname = true
            return [m]
        }
        let key = NameNormalizer.matchKey(name)
        guard !key.isEmpty else { return [] }
        return contacts.filter { contains($0, key) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            .map(\.match)
    }

    /// "contains" on whole words: "minh" matches "Nguyễn Văn Minh" / "Mính", "an" does not match "Lan" or "Tuấn".
    // TODO(spec): §7.2 says "contains"; word boundaries are added so short names do not match inside other names.
    static func contains(_ contact: ContactRecord, _ key: String) -> Bool {
        let forms = [contact.givenName, contact.familyName, contact.displayName,
                     [contact.givenName, contact.middleName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " "),
                     [contact.familyName, contact.givenName].filter { !$0.isEmpty }.joined(separator: " "),     // "Nguyễn Minh"
                     [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")]     // "Minh Nguyễn"
        return forms.contains { form in
            let f = NameNormalizer.normalize(form)
            return !f.isEmpty && " \(f) ".contains(" \(key) ")
        }
    }
}

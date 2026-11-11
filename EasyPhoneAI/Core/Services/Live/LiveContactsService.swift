@preconcurrency import Contacts
import Foundation
import OSLog

/// Contacts on device (ARCHITECTURE §4.2, DATA_MODEL §7.2, spec §6.6). An actor: `CNContactStore` stays isolated and
/// only value types leave. Nicknames are read from `LocalDataRepository` through `nicknameContactId` (main actor).
/// Nothing is logged except error codes (D-059); the contact list never leaves the phone (D-056).
actor LiveContactsService: ContactsService {
    private let store = CNContactStore()
    private let nicknameContactId: @MainActor @Sendable (String) -> String?
    private static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "contacts")

    private static let keys: [CNKeyDescriptor] = [
        CNContactIdentifierKey, CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey,
        CNContactThumbnailImageDataKey, CNContactPhoneNumbersKey,
    ].map { $0 as CNKeyDescriptor }

    init(nicknameContactId: @escaping @MainActor @Sendable (String) -> String?) {
        self.nicknameContactId = nicknameContactId
    }

    func match(name: String) async throws -> [ContactMatch] {
        try ensureAccess()
        let nickname = await nicknameContactId(name)
        return ContactMatcher.match(name, nicknameContactId: nickname, in: try allContacts())
    }

    func phoneNumbers(contactId: String) async throws -> [PhoneEntry] {
        try ensureAccess()
        do {
            let contact = try store.unifiedContact(withIdentifier: contactId, keysToFetch: Self.keys)
            return contact.phoneNumbers.map { labeled in
                PhoneEntry(label: labeled.label.map(CNLabeledValue<CNPhoneNumber>.localizedString(forLabel:)),
                           number: labeled.value.stringValue)
            }
        } catch {
            throw ServiceError.notFound
        }
    }

    // MARK: - Internals

    /// `authorized` and `limited` (iOS 18) can search; `limited` sees only the contacts the user shared.
    private func ensureAccess() throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: return
        default: throw ServiceError.permissionDenied(.contacts)
        }
    }

    private func allContacts() throws -> [ContactRecord] {
        var records: [ContactRecord] = []
        let request = CNContactFetchRequest(keysToFetch: Self.keys)
        request.unifyResults = true
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                records.append(Self.record(contact))
            }
        } catch {
            Self.logger.error("contacts fetch failed: \((error as NSError).code, privacy: .public)")
            // TODO(spec): no `error.contacts.*` key in UI_SCREENS §8; `error.generic` is shown for this code.
            throw ServiceError.framework(code: "contacts.fetchFailed")
        }
        return records
    }

    static func record(_ contact: CNContact) -> ContactRecord {
        ContactRecord(id: contact.identifier, givenName: contact.givenName, middleName: contact.middleName,
                      familyName: contact.familyName, thumbnail: contact.thumbnailImageData,
                      phoneCount: contact.phoneNumbers.count)
    }
}

import Foundation
import Synchronization

/// In-memory `ContactsService` for previews and tests (D-206), same §7.2 rules via `ContactMatcher`.
/// `nicknames` maps a nickname (exact or normalized) to a contact id, like `LocalDataRepository`.
final class MockContactsService: ContactsService {
    private struct State {
        var contacts: [ContactRecord]
        var phones: [String: [PhoneEntry]]
        var nicknames: [String: String]
        var access: PermissionStatus
    }

    private let state: Mutex<State>

    init(_ contacts: [ContactRecord] = [], phones: [String: [PhoneEntry]] = [:], nicknames: [String: String] = [:],
         access: PermissionStatus = .granted) {
        state = Mutex(State(contacts: contacts, phones: phones, nicknames: nicknames, access: access))
    }

    /// `MockScenario.uiTest`: one "anh Minh" with one mobile number (Dữ liệu mẫu, D-189).
    static var uiTest: MockContactsService {
        MockContactsService([ContactRecord(id: "uitest-minh", givenName: "Minh", middleName: "Văn", familyName: "Nguyễn",
                                           phoneCount: 1)],
                            phones: ["uitest-minh": [PhoneEntry(label: "di động", number: "+84901234567")]])
    }

    func setAccess(_ access: PermissionStatus) { state.withLock { $0.access = access } }

    func match(name: String) async throws -> [ContactMatch] {
        try state.withLock { s in
            guard s.access.isUsable else { throw ServiceError.permissionDenied(.contacts) }
            let nickname = s.nicknames[name]
                ?? s.nicknames.first { NameNormalizer.normalize($0.key) == NameNormalizer.normalize(name) }?.value
            return ContactMatcher.match(name, nicknameContactId: nickname, in: s.contacts)
        }
    }

    func contact(id: String) async throws -> ContactMatch? {
        try state.withLock { s in
            guard s.access.isUsable else { throw ServiceError.permissionDenied(.contacts) }
            return s.contacts.first { $0.id == id }?.match
        }
    }

    func phoneNumbers(contactId: String) async throws -> [PhoneEntry] {
        try state.withLock { s in
            guard s.access.isUsable else { throw ServiceError.permissionDenied(.contacts) }
            guard s.contacts.contains(where: { $0.id == contactId }) else { throw ServiceError.notFound }
            return s.phones[contactId] ?? []
        }
    }
}

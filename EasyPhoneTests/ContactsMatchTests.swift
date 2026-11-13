import Contacts
import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.7 — DATA_MODEL §7.2, spec §6.6 AC1–AC2, D-106, D-205 (Vietnamese contact matching is a required MVP test).
@Suite("Contact matching (DATA_MODEL §7.2)")
struct ContactsMatchTests {
    static let contacts: [ContactRecord] = [
        ContactRecord(id: "minh1", givenName: "Minh", middleName: "Văn", familyName: "Nguyễn", phoneCount: 2),
        ContactRecord(id: "minh2", givenName: "Mính", familyName: "Trần", phoneCount: 1),
        ContactRecord(id: "lan", givenName: "Lan", middleName: "Thị", familyName: "Nguyễn", phoneCount: 1),
        ContactRecord(id: "tuan", givenName: "Tuấn", familyName: "Lê", phoneCount: 1),
        ContactRecord(id: "duc", givenName: "Đức", familyName: "Phạm", phoneCount: 1),
        ContactRecord(id: "ba", givenName: "Ba", familyName: "Hoàng", phoneCount: 1),
        ContactRecord(id: "an", givenName: "An", familyName: "Vũ", phoneCount: 0),
    ]

    func ids(_ name: String, nickname: String? = nil) -> [String] {
        ContactMatcher.match(name, nicknameContactId: nickname, in: Self.contacts).map(\.id)
    }

    @Test(arguments: [
        ("anh Minh", ["minh1", "minh2"]),          // kinship stripped, "Mính" folds to "minh" (AC1), never auto-picked
        ("minh", ["minh1", "minh2"]),
        ("MÍNH", ["minh1", "minh2"]),
        ("Nguyễn Văn Minh", ["minh1"]),             // full name, family first
        ("minh nguyen", ["minh1"]),                 // given + family order
        ("chị Lan", ["lan"]),
        ("duc", ["duc"]),                           // đ → d
        ("chú Đức", ["duc"]),
        ("bác Ba", ["ba"]),                         // "ba" is a name here: only the leading kinship word is stripped
        ("an", ["an"]),                             // word match: not inside "Lan" / "Tuấn" / "Hoàng"
        ("Hùng", []),
        ("", []),
    ])
    func vietnameseMatching(_ name: String, _ expected: [String]) {
        #expect(Set(ids(name)) == Set(expected))
        #expect(ids(name).count == expected.count)
    }

    @Test func nicknameWinsAndIsMarked() {
        let m = ContactMatcher.match("mẹ", nicknameContactId: "lan", in: Self.contacts)
        #expect(m.map(\.id) == ["lan"] && m[0].viaNickname)
        #expect(m[0].displayName == "Nguyễn Thị Lan")
        // A nickname whose contact was deleted falls through to name search (here: nothing named "mẹ").
        #expect(ContactMatcher.match("mẹ", nicknameContactId: "gone", in: Self.contacts).isEmpty)
    }

    @Test func kinshipKey() {
        #expect(NameNormalizer.matchKey("anh Minh") == "minh")
        #expect(NameNormalizer.matchKey("ông bà Năm") == "nam")
        #expect(NameNormalizer.matchKey("anh") == "anh")          // only kinship → kept
        #expect(NameNormalizer.matchKey("  Chị   ĐÀO ") == "dao")
    }

    @Test func mockUsesNicknamesExactOrNormalized() async throws {
        let svc = MockContactsService(Self.contacts, phones: ["lan": [PhoneEntry(label: "di động", number: "0901 234 567")]],
                                      nicknames: ["Mẹ": "lan"])
        #expect(try await svc.match(name: "Mẹ").map(\.id) == ["lan"])
        #expect(try await svc.match(name: "me").map(\.id) == ["lan"])          // normalized nickname (§7.2 step 2)
        #expect(try await svc.phoneNumbers(contactId: "lan").first?.number == "0901 234 567")
        await #expect(throws: ServiceError.notFound) { _ = try await svc.phoneNumbers(contactId: "nope") }
        svc.setAccess(.denied)
        await #expect(throws: ServiceError.permissionDenied(.contacts)) { _ = try await svc.match(name: "Lan") }
        svc.setAccess(.limited)                                                  // iOS 18 limited: allowed subset
        #expect(try await svc.match(name: "Lan").map(\.id) == ["lan"])
    }

    @Test func liveRecordMapping() {
        let c = CNMutableContact()
        c.givenName = "Minh"; c.middleName = "Văn"; c.familyName = "Nguyễn"
        c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "0901234567"))]
        let r = LiveContactsService.record(c)
        #expect(r.displayName == "Nguyễn Văn Minh" && r.phoneCount == 1)
    }

    @Test func liveWithoutAccessThrows() async {
        guard ![.authorized, .limited].contains(CNContactStore.authorizationStatus(for: .contacts)) else { return }
        let svc = LiveContactsService { _ in nil }
        await #expect(throws: ServiceError.permissionDenied(.contacts)) { _ = try await svc.match(name: "Minh") }
    }
}

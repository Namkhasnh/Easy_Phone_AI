import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.8 — DATA_MODEL §7.3, D-253, D-205 (phone normalization is a required MVP test).
@Suite("Phone normalization + masking (DATA_MODEL §7.3)")
struct PhoneNumberTests {
    @Test(arguments: [
        ("0901234567", "+84901234567"),
        ("0901 234 567", "+84901234567"),
        ("090.123.4567", "+84901234567"),
        ("090-123-4567", "+84901234567"),
        ("(090) 123 4567", "+84901234567"),
        ("090\u{00A0}123\u{00A0}4567", "+84901234567"),     // non-breaking spaces from Contacts
        ("+84 90 123 4567", "+84901234567"),
        ("+84901234567", "+84901234567"),
        ("0084 901 234 567", "+84901234567"),
    ])
    func normalizes(_ raw: String, _ expected: String) {
        #expect(PhoneNumber.normalize(raw) == expected)
    }

    /// §7.3 only knows the 10-digit local form; 11-digit landlines ("024 3xxx xxxx") are not normalized (DOC-40).
    @Test func landlineIsNotInTheSpecPattern() {
        #expect(PhoneNumber.normalize("0283 822 1234") == nil)
        #expect(PhoneNumber.normalize("+84 28 3822 1234") == "+842838221234")   // already E.164 → kept
    }

    @Test(arguments: ["", "113", "12345", "abc", "09012345678", "090123456", "+0901234567", "Minh", "0901 234 56a"])
    func rejects(_ raw: String) {
        #expect(PhoneNumber.normalize(raw) == nil)
        #expect(!PhoneNumber.isPhone(raw))
    }

    @Test func masking() {
        #expect(PhoneNumber.masked("0901 234 567") == "•••• 567")
        #expect(PhoneNumber.masked("+84901234567") == "•••• 567")
        #expect(PhoneNumber.masked("113") == "•••• 113")                    // not normalizable → raw digits
        #expect(!PhoneNumber.masked("0901234567").contains("0901"))         // never the full number
    }

    @Test func sameNumberDifferentWriting() {
        #expect(PhoneNumber.same("0901 234 567", "+84 90 123 4567"))
        #expect(!PhoneNumber.same("0901234567", "0901234568"))
        #expect(!PhoneNumber.same("113", "113"))
    }

    @Test func validatorUsesIt() {                                            // D-253 path in Validator
        #expect(Validator.isPhoneNumber("0901 234 567") && !Validator.isPhoneNumber("anh Minh"))
        #expect(Validator.normalizePhone("(090) 123-4567") == "+84901234567")
    }
}

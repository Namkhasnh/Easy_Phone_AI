import Foundation
import Testing
@testable import EasyPhoneAI

/// 1A.7 — DATA_MODEL §7.1 + §4.1 (D-247, D-248, D-253) + §13 "`validate()` per §4.1 row".
@Suite("Validator (DATA_MODEL §7.1)")
struct ValidatorTests {
    /// 2026-11-09T10:00:00+07:00
    static let now = Validator.parseDateTime("2026-11-09T10:00:00+07:00")!
    static let future = "2026-11-10T08:00:00+07:00"

    /// A step with every catalog field of `(kind, op)`, values from `values` (missing key = empty).
    static func step(_ kind: TaskKind, _ op: TaskOperation, _ values: [String: String],
                     targetRef: String? = nil) -> TaskStep {
        let fields = FieldCatalog.mvp.fields(kind, op).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], deviceOnly: $0.deviceOnly)
        }
        return TaskStep(order: 0, kind: kind, operation: op, fields: fields, targetRef: targetRef)
    }

    static func issues(_ s: TaskStep, serviceIds: Set<String> = []) -> [ValidationIssue] {
        Validator.validate(s, now: now, serviceIds: serviceIds)
    }

    static func missing(_ ids: String...) -> [ValidationIssue] {
        ids.map { ValidationIssue(fieldId: $0, reason: .missing) }
    }

    static let targetRefIssue = ValidationIssue(fieldId: nil, reason: .missingTargetRef)

    // MARK: - §4.1, one test per row (complete → no issue; empty → exactly the required set, catalog order)

    struct Row: Sendable, CustomTestStringConvertible {
        let kind: TaskKind, op: TaskOperation
        let valid: [String: String]
        let requiredInOrder: [String]
        let targetRef: Bool
        var testDescription: String { "\(kind.rawValue).\(op.rawValue)" }
    }

    static let rows: [Row] = [
        Row(kind: .calendarEvent, op: .create, valid: ["title": "Khám răng", "startDate": future],
            requiredInOrder: ["title", "startDate"], targetRef: false),
        Row(kind: .calendarEvent, op: .update, valid: ["title": "Khám răng", "startDate": future],
            requiredInOrder: ["title", "startDate"], targetRef: true),
        Row(kind: .calendarEvent, op: .delete, valid: [:], requiredInOrder: [], targetRef: true),
        Row(kind: .reminder, op: .create, valid: ["title": "Uống thuốc", "dueDate": future],
            requiredInOrder: ["title", "dueDate"], targetRef: false),
        Row(kind: .reminder, op: .update, valid: ["title": "Uống thuốc", "dueDate": future],
            requiredInOrder: ["title", "dueDate"], targetRef: true),
        Row(kind: .reminder, op: .complete, valid: ["completed": "true"], requiredInOrder: ["completed"], targetRef: true),
        Row(kind: .reminder, op: .snooze, valid: ["snoozeOption": "hour1"], requiredInOrder: ["snoozeOption"], targetRef: true),
        Row(kind: .reminder, op: .delete, valid: [:], requiredInOrder: [], targetRef: true),
        Row(kind: .call, op: .open, valid: ["recipientName": "mẹ", "contactId": "C1", "phoneNumber": "+84901234567"],
            requiredInOrder: ["recipientName", "contactId", "phoneNumber"], targetRef: false),
        Row(kind: .sms, op: .open,
            valid: ["recipientName": "anh Minh", "contactId": "C1", "phoneNumber": "+84901234567",
                    "body": "Chiều nay em đến muộn nhé.", "channel": "sms"],
            requiredInOrder: ["recipientName", "body", "channel"], targetRef: false),   // empty channel → no sms extras
        Row(kind: .place, op: .create,
            valid: ["query": "nhà", "name": "Nhà", "address": "123 Lê Lợi, Q1", "coordinate": "10.7769,106.7009",
                    "label": "home"],
            requiredInOrder: ["query", "name", "address", "coordinate", "label"], targetRef: false),
        Row(kind: .place, op: .open,
            valid: ["query": "chợ", "name": "Chợ Bến Thành", "address": "Lê Lợi, Q1", "coordinate": "10.772,106.698",
                    "mapsApp": "appleMaps"],
            requiredInOrder: ["query", "name", "address", "coordinate", "mapsApp"], targetRef: false),
        Row(kind: .ocr, op: .create, valid: ["extractedText": "Hẹn khám 14:00"],
            requiredInOrder: ["extractedText"], targetRef: false),
    ]

    @Test(arguments: rows) func completeRowHasNoIssue(_ row: Row) {
        let s = Self.step(row.kind, row.op, row.valid, targetRef: row.targetRef ? "ek-1" : nil)
        #expect(Self.issues(s) == [])
    }

    @Test(arguments: rows) func emptyRowListsRequiredSetInOrder(_ row: Row) {
        let expected = (row.targetRef ? [Self.targetRefIssue] : []) + row.requiredInOrder.map {
            ValidationIssue(fieldId: $0, reason: .missing)
        }
        #expect(Self.issues(Self.step(row.kind, row.op, [:])) == expected)
    }

    @Test func everyCatalogPairHasARow() {
        let covered = Set(Self.rows.map { "\($0.kind.rawValue).\($0.op.rawValue)" })
        let catalog = Set(FieldCatalog.mvp.kinds.flatMap { k in k.required.map { "\(k.kind.rawValue).\($0.operation.rawValue)" } })
        #expect(covered == catalog)
    }

    @Test func unsupportedPair() {
        let s = TaskStep(order: 0, kind: .call, operation: .delete)
        #expect(Self.issues(s) == [ValidationIssue(fieldId: nil, reason: .unsupportedOperation)])
        #expect(Self.issues(TaskStep(order: 0, kind: .ride, operation: .prepare)).first?.reason == .unsupportedOperation)
    }

    // MARK: - channel (D-247) and phone-number recipient (D-253)

    @Test func smsChannelRequiresContactAndNumber() {
        let s = Self.step(.sms, .open, ["recipientName": "anh Minh", "body": "Hi", "channel": "sms"])
        #expect(Self.issues(s) == Self.missing("contactId", "phoneNumber"))
    }

    @Test func otherChannelIsCopyOnly() {
        let s = Self.step(.sms, .open, ["recipientName": "anh Minh", "body": "Hi", "channel": "zalo"])
        #expect(Self.issues(s, serviceIds: ["zalo"]) == [])                              // no contact needed
        #expect(Self.issues(s) == [ValidationIssue(fieldId: "channel", reason: .unknownOption)])   // not in SupportedServices
        #expect(!Validator.requiredFieldIds(s).contains("phoneNumber"))
    }

    @Test func phoneNumberRecipientSkipsContactId() {
        let call = Self.step(.call, .open, ["recipientName": "0901 234 567", "phoneNumber": "+84901234567"])
        #expect(Self.issues(call) == [])
        let sms = Self.step(.sms, .open, ["recipientName": "090.123.4567", "body": "Hi", "channel": "sms"])
        #expect(Self.issues(sms) == Self.missing("phoneNumber"))
    }

    @Test func phoneNumberDetection() {
        #expect(Validator.isPhoneNumber("0901 234 567"))
        #expect(Validator.isPhoneNumber("090-123-4567"))
        #expect(Validator.isPhoneNumber("+84901234567"))
        #expect(!Validator.isPhoneNumber("anh Minh"))
        #expect(!Validator.isPhoneNumber("12345"))
        #expect(!Validator.isPhoneNumber(nil))
    }

    @Test func customLabelRequiredOnlyForCustom() {
        var values = ["query": "nhà con gái", "name": "Nhà Lan", "address": "1 Hai Bà Trưng", "coordinate": "21.0,105.8",
                      "label": "custom"]
        #expect(Self.issues(Self.step(.place, .create, values)) == Self.missing("customLabel"))
        values["customLabel"] = "Nhà con gái"
        #expect(Self.issues(Self.step(.place, .create, values)) == [])
    }

    @Test func applyRequiredFollowsChannel() {
        var s = Self.step(.sms, .open, ["channel": "sms"])
        s = Validator.applyRequired(s)
        #expect(s.field("phoneNumber")?.required == true)
        s.fields[s.fields.firstIndex { $0.id == "channel" }!].value = "zalo"
        s = Validator.applyRequired(s)
        #expect(s.field("phoneNumber")?.required == false)
        #expect(s.field("contactId")?.required == false)
        #expect(s.field("body")?.required == true)
    }

    // MARK: - ambiguity, encoding, cross-field

    @Test func ambiguityBlocksEvenOptionalField() {
        var s = Self.step(.calendarEvent, .create, ["title": "Họp", "startDate": Self.future])
        let i = s.fields.firstIndex { $0.id == "location" }!
        s.fields[i].ambiguity = Ambiguity(kind: .place, question: "Ở đâu?", candidates: [])
        #expect(Self.issues(s) == [ValidationIssue(fieldId: "location", reason: .ambiguous)])
    }

    @Test func invalidEncodingOnRequiredField() {
        let s = Self.step(.calendarEvent, .create, ["title": "Họp", "startDate": "mai 8 giờ"])
        #expect(Self.issues(s) == [ValidationIssue(fieldId: "startDate", reason: .invalidEncoding)])
        let r = Self.step(.reminder, .snooze, ["snoozeOption": "week1"], targetRef: "r1")
        #expect(Self.issues(r) == [ValidationIssue(fieldId: "snoozeOption", reason: .unknownOption)])
        let c = Self.step(.reminder, .complete, ["completed": "yes"], targetRef: "r1")
        #expect(Self.issues(c) == [ValidationIssue(fieldId: "completed", reason: .invalidEncoding)])
    }

    @Test func whitespaceOnlyIsMissing() {
        let s = Self.step(.calendarEvent, .create, ["title": "   ", "startDate": Self.future])
        #expect(Self.issues(s) == Self.missing("title"))
    }

    @Test func endMustBeAfterStart() {
        var values = ["title": "Họp", "startDate": Self.future, "endDate": Self.future]
        #expect(Self.issues(Self.step(.calendarEvent, .create, values))
            == [ValidationIssue(fieldId: "endDate", reason: .endBeforeStart)])
        values["endDate"] = "2026-11-10T09:00:00+07:00"
        #expect(Self.issues(Self.step(.calendarEvent, .create, values)) == [])
    }

    @Test func pastToleranceIsFiveMinutes() {
        let fourMin = "2026-11-09T09:56:00+07:00", sixMin = "2026-11-09T09:54:00+07:00"
        #expect(Self.issues(Self.step(.reminder, .create, ["title": "A", "dueDate": fourMin])) == [])
        #expect(Self.issues(Self.step(.reminder, .create, ["title": "A", "dueDate": sixMin]))
            == [ValidationIssue(fieldId: "dueDate", reason: .inPast)])
        // Different offset, same instant rules: 02:54Z = 09:54+07:00.
        #expect(Self.issues(Self.step(.calendarEvent, .create, ["title": "A", "startDate": "2026-11-09T02:54:00Z"]))
            == [ValidationIssue(fieldId: "startDate", reason: .inPast)])
    }

    @Test func deleteHintsAreNotChecked() {
        let s = Self.step(.calendarEvent, .delete, ["title": "Họp", "startDate": "2020-01-01T08:00:00+07:00"],
                          targetRef: "ek-1")
        #expect(Self.issues(s) == [])
    }

    @Test func encodings() {
        #expect(Validator.isEncoded("2026-11-09T14:00:00+07:00", as: .dateTime))
        #expect(Validator.isEncoded("2026-11-09T14:00:00.500Z", as: .dateTime))
        #expect(!Validator.isEncoded("2026-11-09T14:00:00", as: .dateTime))        // no offset
        #expect(!Validator.isEncoded("2026-11-09", as: .dateTime))
        #expect(Validator.isEncoded("2026-11-14", as: .date))
        #expect(!Validator.isEncoded("2026-02-30", as: .date))
        #expect(Validator.isEncoded("30", as: .durationMinutes))
        #expect(!Validator.isEncoded("-5", as: .durationMinutes))
        #expect(!Validator.isEncoded("٣٠", as: .durationMinutes))                   // non-ASCII digits
        #expect(Validator.isEncoded("+84901234567", as: .phone))
        #expect(!Validator.isEncoded("0901234567", as: .phone))                     // must be E.164 after normalization
        #expect(Validator.isEncoded("10.7769,106.7009", as: .coordinate))
        #expect(!Validator.isEncoded("100,0", as: .coordinate))
        #expect(!Validator.isEncoded(" Khám", as: .text))                            // must be trimmed
        #expect(!Validator.isEncoded(String(repeating: "a", count: 2001), as: .text))
        #expect(!Validator.isEncoded(String(repeating: "a", count: 10_001), as: .longText))
        #expect(!Validator.isEncoded("1 Lê Lợi\nQ1", as: .address))
    }
}

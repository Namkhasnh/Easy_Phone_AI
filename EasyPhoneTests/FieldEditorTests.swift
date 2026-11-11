import Foundation
import Testing
@testable import EasyPhoneAI

/// 1A.12 — UI_SCREENS S05, DATA_MODEL §1.6 encodings, §7.1 cross-field, §7.3 phone normalization.
@MainActor
@Suite("Field editor (UI_SCREENS S05)")
struct FieldEditorTests {
    static let tz = "Asia/Ho_Chi_Minh"
    static let now = Validator.parseDateTime("2026-11-09T10:20:00+07:00")!

    static func editor(_ field: Field, kind: TaskKind = .reminder, op: TaskOperation = .create,
                       others: [Field] = [], saved: @escaping (String?) -> Void = { _ in }) -> FieldEditorViewModel {
        let step = TaskStep(order: 0, kind: kind, operation: op, fields: [field] + others)
        return FieldEditorViewModel(field: field, step: step, timeZoneId: tz, now: { now }, onSave: saved)
    }

    @Test func phoneNormalization() {
        #expect(Validator.normalizePhone("0901 234 567") == "+84901234567")
        #expect(Validator.normalizePhone("090.123.4567") == "+84901234567")
        #expect(Validator.normalizePhone("+84 90 123 4567") == "+84901234567")
        #expect(Validator.normalizePhone("12345") == nil)
    }

    @Test func phoneEditorSavesE164OrShowsError() {
        var saved: String?
        let vm = Self.editor(Field(id: "phoneNumber", type: .phone), kind: .call, op: .open) { saved = $0 }
        vm.text = "0901 234 567"
        #expect(vm.encodedValue == "+84901234567" && vm.canSave)
        vm.save()
        #expect(saved == "+84901234567")
        vm.text = "0901"
        #expect(vm.invalidMessage == UserMessage(key: "editor.invalid.phone"))
        #expect(!vm.canSave)
    }

    @Test func textIsTrimmedAndLengthChecked() {
        let vm = Self.editor(Field(id: "title", type: .text, value: "  Uống thuốc  "))
        #expect(vm.encodedValue == "Uống thuốc")
        vm.text = String(repeating: "a", count: 2001)
        #expect(vm.invalidMessage == UserMessage(key: "editor.invalid.tooLong", args: ["2000"]))
        #expect(vm.invalidMessage?.text == "Nội dung quá dài (tối đa 2000 ký tự).")
        vm.clear()
        #expect(vm.encodedValue == nil && vm.canSave)          // empty is allowed; Review shows "Chưa có"
    }

    @Test func dateTimeEncodesInDraftTimeZone() {
        let vm = Self.editor(Field(id: "dueDate", type: .dateTime, value: "2026-11-10T08:30:00+07:00"))
        #expect(vm.encodedValue == "2026-11-10T08:30:00+07:00")
        vm.setDay(offset: 0)                                    // "Hôm nay": keep 08:30
        #expect(vm.encodedValue == "2026-11-09T08:30:00+07:00")
        #expect(vm.invalidMessage == UserMessage(key: "editor.invalid.past"))   // 08:30 < 10:20 − 5 min
        vm.setDay(offset: 1)                                    // "Ngày mai"
        #expect(vm.encodedValue == "2026-11-10T08:30:00+07:00" && vm.canSave)
    }

    @Test func emptyDateTimeStartsAtNextFullHour() {
        let vm = Self.editor(Field(id: "dueDate", type: .dateTime))
        #expect(vm.encodedValue == "2026-11-09T11:00:00+07:00")
    }

    @Test func endBeforeStartIsFlagged() {
        let start = Field(id: "startDate", type: .dateTime, value: "2026-11-10T09:00:00+07:00")
        let vm = Self.editor(Field(id: "endDate", type: .dateTime, value: "2026-11-10T08:00:00+07:00"),
                             kind: .calendarEvent, others: [start, Field(id: "title", type: .text, value: "Họp")])
        #expect(vm.invalidMessage == UserMessage(key: "editor.invalid.endBeforeStart"))
    }

    @Test func alertChoicesKeepAIValue() {
        let vm = Self.editor(Field(id: "alertMinutesBefore", type: .durationMinutes, value: "45"), kind: .calendarEvent)
        #expect(vm.options == ["0", "15", "60", "1440", "45"])
        #expect(vm.optionLabel("60") == "Trước 1 tiếng")
        let channel = Self.editor(Field(id: "channel", type: .enumChoice, value: "sms"), kind: .sms, op: .open)
        #expect(channel.options == ["sms"])
        #expect(channel.optionLabel("sms") == "Tin nhắn (SMS/iMessage)")
    }

    @Test func dateFieldEncodesDay() {
        let vm = Self.editor(Field(id: "x", type: .date, value: "2026-11-14"))
        #expect(vm.encodedValue == "2026-11-14")
    }

    // MARK: - Wired to Review (S04 → S05 → engine)

    @Test func reviewSaveGoesThroughEngine() {
        let repo = MockTaskRepository()
        let engine = TaskEngine(repository: repo, now: { Self.now })
        let fields = FieldCatalog.mvp.fields(.reminder, .create).map {
            Field(id: $0.id, type: $0.type, value: ["title": "Uống thuốc"][$0.id], source: .ai, confidence: 0.9)
        }
        let step = TaskStep(order: 0, kind: .reminder, operation: .create, fields: fields)
        let draft = TaskDraft(inputMode: .text, originalInput: "x", timeZoneId: Self.tz, steps: [step])
        repo.save(draft)
        engine.revalidate(stepId: step.id, in: draft)
        let review = ReviewViewModel(draftId: draft.id, repository: repo, engine: engine,
                                     permissions: MockPermissionManager(), now: { Self.now })
        #expect(review.step?.state == .needsInfo)

        review.tapRow(review.visibleFields.first { $0.id == "dueDate" }!)
        let editor = try! #require(review.editor)
        editor.setDay(offset: 1)
        editor.save()

        let due = review.step?.field("dueDate")
        #expect(due?.value == "2026-11-10T11:00:00+07:00")
        #expect(due?.source == .user)
        #expect(review.step?.state == .awaitingApproval)       // engine re-validated (D-104 autosave)
    }

    @Test func pickerTypesDoNotOpenS05() {
        #expect(!ReviewViewModel.isEditableInS05(.contactRef))
        #expect(!ReviewViewModel.isEditableInS05(.coordinate))
        #expect(ReviewViewModel.isEditableInS05(.dateTime))
    }
}

import Foundation
import Testing
@testable import EasyPhoneAI

/// 1A.11a — UI_SCREENS S04, §5 `common.dateTimeFormat`, §10.3 options; DATA_MODEL §3.3 linked-step rule.
@Suite("FieldFormatter (UI_SCREENS §5, §10.3)")
struct FieldFormatterTests {
    static let tz = "Asia/Ho_Chi_Minh"

    @Test func dateTimeInDraftTimeZone() {
        let f = Field(id: "startDate", type: .dateTime, value: "2026-11-09T07:00:00Z")      // 14:00 in VN
        #expect(FieldFormatter.display(f, timeZoneId: Self.tz) == "Thứ Hai, 09/11 lúc 14:00")
        let sunday = Field(id: "dueDate", type: .dateTime, value: "2026-11-15T08:05:00+07:00")
        #expect(FieldFormatter.display(sunday, timeZoneId: Self.tz) == "Chủ Nhật, 15/11 lúc 08:05")
    }

    @Test func optionsAndAlert() {
        #expect(FieldFormatter.display(Field(id: "channel", type: .enumChoice, value: "sms"), timeZoneId: Self.tz)
            == "Tin nhắn (SMS/iMessage)")
        #expect(FieldFormatter.display(Field(id: "alertMinutesBefore", type: .durationMinutes, value: "60"),
                                       timeZoneId: Self.tz) == "Trước 1 tiếng")
        #expect(FieldFormatter.display(Field(id: "alertMinutesBefore", type: .durationMinutes, value: "45"),
                                       timeZoneId: Self.tz) == "45")                    // AI value kept (P-35)
        #expect(FieldFormatter.display(Field(id: "snoozeOption", type: .enumChoice, value: "tomorrowMorning"),
                                       timeZoneId: Self.tz, snoozeMorningHour: 7) == "Sáng mai lúc 7 giờ")
    }

    @Test func emptyAndLockedValuesShowNothing() {
        #expect(FieldFormatter.display(Field(id: "notes", type: .longText), timeZoneId: Self.tz) == nil)
        #expect(FieldFormatter.display(Field(id: "notes", type: .longText, value: ""), timeZoneId: Self.tz) == nil)
        #expect(FieldFormatter.display(Field(id: "contactId", type: .contactRef, value: "ABC-123", deviceOnly: true),
                                       timeZoneId: Self.tz) == nil)                      // 🔒 never shown raw
        #expect(FieldFormatter.display(Field(id: "allDay", type: .bool, value: "true"), timeZoneId: Self.tz) == "Có")
    }
}

@MainActor
@Suite("Review (UI_SCREENS S04)")
struct ReviewViewModelTests {
    static let now = Validator.parseDateTime("2026-11-09T10:00:00+07:00")!
    let repo = MockTaskRepository()
    let permissions = MockPermissionManager()
    let engine: TaskEngine

    init() { engine = TaskEngine(repository: repo, now: { Self.now }) }

    func step(_ kind: TaskKind, _ op: TaskOperation, order: Int = 0, _ values: [String: String],
              targetRef: String? = nil) -> TaskStep {
        let fields = FieldCatalog.mvp.fields(kind, op).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, confidence: 0.9, deviceOnly: $0.deviceOnly)
        }
        return TaskStep(order: order, kind: kind, operation: op, fields: fields, targetRef: targetRef)
    }

    func open(_ steps: [TaskStep], input: String = "x") -> ReviewViewModel {
        let d = TaskDraft(inputMode: .text, originalInput: input, timeZoneId: "Asia/Ho_Chi_Minh", steps: steps)
        repo.save(d)
        for s in steps { engine.revalidate(stepId: s.id, in: d) }
        return ReviewViewModel(draftId: d.id, repository: repo, engine: engine, permissions: permissions)
    }

    static let reminderOK = ["title": "Uống thuốc", "dueDate": "2026-11-10T08:00:00+07:00"]

    @Test func readyReminderCanBeConfirmed() {
        let vm = open([step(.reminder, .create, Self.reminderOK)], input: "Nhắc tôi uống thuốc")
        #expect(vm.titleKey == "step.reminder.create")
        #expect(vm.stepPosition == nil)
        #expect(vm.visibleFields.map(\.id) == ["title", "dueDate", "notes"])
        #expect(vm.blocker == nil && vm.disabledReasonKey == nil)
        #expect(vm.showsActionBar && !vm.isDelete)
        #expect(vm.originalInput == "Bạn đã yêu cầu: “Nhắc tôi uống thuốc”")
    }

    @Test func missingAndAmbiguityReasons() {
        let vm = open([step(.reminder, .create, ["title": "Uống thuốc"])])
        #expect(vm.disabledReasonKey == "review.disabled.missing")

        var s = step(.reminder, .create, Self.reminderOK)
        s.fields[0].ambiguity = Ambiguity(kind: .other, question: "?", candidates: [])
        #expect(open([s]).disabledReasonKey == "review.disabled.ambiguity")
    }

    @Test func secondLinkedStepWaitsForFirst() {          // DATA_MODEL §3.3
        let first = step(.calendarEvent, .create, order: 0, ["title": "Khám", "startDate": "2026-11-10T08:00:00+07:00"])
        let second = step(.reminder, .create, order: 1, Self.reminderOK)
        let vm = open([first, second])
        let draft = vm.draft!
        #expect(engine.confirmBlocker(stepId: second.id, in: draft) == .previousStep)
        #expect(vm.stepPosition?.current == 1 && vm.stepPosition?.total == 2)

        draft.steps[0].state = .handedOff                   // test setup only
        #expect(engine.confirmBlocker(stepId: second.id, in: draft) == nil)
        draft.steps[0].state = .failed                       // final (D-122) also unblocks
        #expect(engine.confirmBlocker(stepId: second.id, in: draft) == nil)
    }

    @Test func confirmRefusesBlockedLinkedStep() async {
        let exec = MockStepExecutor(outcome: .verified(evidence: "ek:reminder:R"))
        let e = TaskEngine(repository: repo, executors: [.reminder: exec], now: { Self.now })
        let first = step(.calendarEvent, .create, order: 0, ["title": "Khám", "startDate": "2026-11-10T08:00:00+07:00"])
        let second = step(.reminder, .create, order: 1, Self.reminderOK)
        let d = TaskDraft(inputMode: .text, originalInput: "x", steps: [first, second])
        for s in [first, second] { e.revalidate(stepId: s.id, in: d) }
        #expect(await e.confirm(stepId: second.id, in: d) == .notAllowed)
        #expect(exec.executed.isEmpty)
    }

    @Test func smsHidesContactRowsForOtherChannel() {
        let vm = open([step(.sms, .open, ["recipientName": "anh Minh", "body": "Hi", "channel": "viber"])])
        #expect(vm.visibleFields.map(\.id) == ["recipientName", "body", "channel"])       // copy-only (D-247)
        let zalo = open([step(.sms, .open, ["recipientName": "anh Minh", "body": "Hi", "channel": "zalo"])])
        #expect(zalo.visibleFields.map(\.id) == ["recipientName", "contactId", "phoneNumber", "body", "channel"])  // D-297
        let sms = open([step(.sms, .open, ["recipientName": "anh Minh", "body": "Hi", "channel": "sms"])])
        #expect(sms.visibleFields.map(\.id) == ["recipientName", "contactId", "phoneNumber", "body", "channel"])  // 🔒 rows shown by name (1C.9)
    }

    @Test func deleteUsesDestructiveVariant() {
        let vm = open([step(.calendarEvent, .delete, ["title": "Khám"], targetRef: "E1")])
        #expect(vm.isDelete && vm.blocker == nil)
    }

    @Test func editStartsAtFirstFieldNeedingReview() {
        var s = step(.reminder, .create, Self.reminderOK)
        s.fields[1].confidence = 0.4                         // dueDate
        let vm = open([s])
        vm.startEdit()
        #expect(vm.editingFieldId == "dueDate")
        let plain = open([step(.reminder, .create, Self.reminderOK)])
        plain.startEdit()
        #expect(plain.editingFieldId == "title")
    }

    @Test func editAfterApprovalShowsBanner() async {
        let vm = open([step(.reminder, .create, Self.reminderOK)])
        let d = vm.draft!, id = vm.stepId!
        engine.apply(.userConfirmed, stepId: id, in: d)      // simulate an earlier approval
        engine.apply(.actionVerified, stepId: id, in: d)
        d.steps[0].resultEvidence = "ek:reminder:R1"
        vm.edit(fieldId: "title", value: "Uống thuốc huyết áp")
        #expect(vm.step?.state == .awaitingApproval)
        #expect(vm.banner == UserMessage(key: "review.editedAfterApproval"))
    }

    @Test func cancelClosesAndKeepsDraft() {
        let vm = open([step(.reminder, .create, Self.reminderOK)])
        vm.cancel()
        #expect(vm.didClose)
        #expect(vm.step?.state == .cancelled)
        #expect(repo.draft(vm.draft!.id) != nil)
        #expect(!vm.showsActionBar)
    }

    // MARK: - Result card (1A.11b, D-250)

    func confirmed(_ outcome: ExecutionOutcome, kind: TaskKind = .reminder, extraStep: Bool = false) async -> ReviewViewModel {
        let exec = MockStepExecutor(outcome: outcome)
        var executors: [TaskKind: any StepExecutor] = [.reminder: exec]
        executors[kind] = exec                                   // no duplicate keys in a literal (runtime trap)
        let e = TaskEngine(repository: repo, executors: executors, now: { Self.now })
        var steps: [TaskStep]
        if kind == .call {
            steps = [step(.call, .open, ["recipientName": "0901234567", "phoneNumber": "+84901234567"])]
        } else {
            steps = [step(.reminder, .create, Self.reminderOK)]
        }
        if extraStep { steps.append(step(.reminder, .create, order: 1, Self.reminderOK)) }
        let d = TaskDraft(inputMode: .text, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh", steps: steps)
        repo.save(d)
        for s in steps { e.revalidate(stepId: s.id, in: d) }
        let vm = ReviewViewModel(draftId: d.id, repository: repo, engine: e, permissions: MockPermissionManager())
        await vm.confirm()
        return vm
    }

    @Test func succeededLastStepSaysAllDoneAndDone() async {
        let vm = await confirmed(.verified(evidence: "ek:reminder:R1"))
        let card = vm.resultCard
        #expect(!vm.showsActionBar)
        #expect(card?.state == .succeeded)
        #expect(card?.message == "Xong rồi!")
        #expect(card?.primary == .init(title: "Xong", action: .done))
        vm.perform(.done)
        #expect(vm.didFinish)
    }

    @Test func succeededWithNextStepOffersContinue() async {
        let vm = await confirmed(.verified(evidence: "ek:reminder:R1"), extraStep: true)
        let card = vm.resultCard
        #expect(card?.message == "Đã tạo lời nhắc.")
        #expect(card?.primary?.title == "Tiếp tục: Tạo lời nhắc")
        guard case .nextStep(let next)? = card?.primary?.action else { Issue.record("no next"); return }
        vm.perform(.nextStep(next))
        #expect(vm.stepId == next)
        #expect(vm.stepPosition?.current == 2)
        #expect(vm.blocker == nil)                            // previous step succeeded → confirmable
    }

    @Test func handedOffCallOffersMarkDoneAndLater() async {
        let vm = await confirmed(.handedOff(note: "x"), kind: .call)
        let card = vm.resultCard
        #expect(card?.message == "Cần hoàn tất cuộc gọi trong ứng dụng Điện thoại.")
        #expect(card?.primary?.action == .markDone && card?.secondary?.action == .later)
        vm.perform(.markDone)
        #expect(vm.step?.state == .userMarkedDone)            // D-242: only by the user's tap
    }

    @Test func failedShowsErrorAndRetryCancel() async {
        let vm = await confirmed(.failed(code: "approval.mismatch"))
        let card = vm.resultCard
        #expect(card?.message == "Không thành công.")
        #expect(card?.detail == "Thông tin đã thay đổi, vui lòng xác nhận lại")
        #expect(card?.primary?.action == .retry && card?.secondary?.action == .cancel)
        vm.perform(.retry)
        #expect(vm.step?.state == .awaitingApproval && vm.showsActionBar)

        let unknownCode = await confirmed(.failed(code: "something.new"))
        #expect(unknownCode.resultCard?.detail == "Có lỗi xảy ra. Bạn thử lại nhé.")
    }

    @Test func unknownCalendarOrReminderCanRetry() {
        let vm = open([step(.reminder, .create, Self.reminderOK)])
        vm.draft!.steps[0].state = .unknown                   // test setup only
        let card = vm.resultCard
        #expect(card?.message == "Chưa rõ kết quả. Mình sẽ kiểm tra lại khi bạn mở ứng dụng.")
        #expect(card?.primary?.action == .markDone && card?.secondary?.action == .retry)
    }

    @Test func processingShowsNoButtons() {
        let vm = open([step(.reminder, .create, Self.reminderOK)])
        vm.draft!.steps[0].state = .processing               // test setup only
        #expect(vm.resultCard == .init(state: .processing, message: "Đang thực hiện…", detail: nil,
                                       primary: nil, secondary: nil))
    }
}

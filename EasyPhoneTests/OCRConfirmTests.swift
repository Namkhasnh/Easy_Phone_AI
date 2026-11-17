import Foundation
import Testing
@testable import EasyPhoneAI

/// 1D.7b — "Tiếp tục" on the `ocr` step: `OCRExecutor` (`local:confirmed`), the linked calendarEvent / reminder step
/// (DATA_MODEL §3.3, §3.5, §4), `copyContactInfo` → clipboard (D-226), S04 label + radio + jump to the next step;
/// 1D.7c "Đọc to" on `extractedText` + "Chụp lại" (UI_SCREENS S09 step 3).
@MainActor
@Suite("ocr step confirm → linked step")
struct OCRConfirmTests {
    let text = OCRResult.sample.text
    /// Before `ExtractResponse.mock` dateTime (2026-11-14 09:30 +07), so the linked date is not "in the past".
    let now = ISO8601DateFormatter().date(from: "2026-11-10T08:00:00+07:00")!

    private func setUp(action: String?, system: MockSystemService = MockSystemService())
        -> (TaskEngine, TaskDraft, MockTaskRepository) {
        let repo = MockTaskRepository()
        let fixed = now
        let engine = TaskEngine(repository: repo, executors: [.ocr: OCRExecutor(system: system)], now: { fixed })
        let draft = TaskDraft(inputMode: .photo, originalInput: text)
        repo.save(draft)
        engine.applyExtract(.mock, text: text, to: draft)
        engine.edit(fieldId: "nextAction", value: action, stepId: draft.steps[0].id, in: draft)
        return (engine, draft, repo)
    }

    @Test func confirmSucceedsWithLocalEvidence() async {
        let (engine, draft, _) = setUp(action: nil)
        let result = await engine.confirm(stepId: draft.steps[0].id, in: draft)
        #expect(result == .finished(.succeeded))
        #expect(draft.steps[0].resultEvidence == "local:confirmed")
        #expect(draft.steps.count == 1)                                          // no nextAction → no step
    }

    @Test func calendarEventIsAppendedWithLinkedFields() async {
        let (engine, draft, repo) = setUp(action: "calendarEvent")
        let ocr = draft.steps[0]
        #expect(await engine.confirm(stepId: ocr.id, in: draft) == .finished(.succeeded))
        #expect(draft.steps.count == 2)
        let event = draft.steps[1]
        #expect(event.kind == .calendarEvent && event.operation == .create && event.order == 1)
        #expect(event.field("title")?.value == "Phòng khám Nha khoa An Bình")
        #expect(event.field("title")?.source == .linked(stepId: ocr.id, fieldId: "title"))
        #expect(event.field("startDate")?.value == "2026-11-14T09:30:00+07:00")
        #expect(event.field("startDate")?.source == .linked(stepId: ocr.id, fieldId: "dateTime"))
        #expect(event.field("location")?.value == "215 Hồng Bàng, Q5")
        #expect(event.field("location")?.source == .linked(stepId: ocr.id, fieldId: "address"))
        #expect(event.field("alertMinutesBefore")?.value == "60")                // catalog default
        #expect(event.field("notes")?.value == nil)                              // name / phone not carried over
        #expect(event.state == .awaitingApproval)                                // nothing runs before its own tap
        #expect(repo.draft(draft.id)?.steps.count == 2)
    }

    @Test func reminderGetsDueDateAndNoLocation() async {
        let (engine, draft, _) = setUp(action: "reminder")
        _ = await engine.confirm(stepId: draft.steps[0].id, in: draft)
        let reminder = draft.steps[1]
        #expect(reminder.kind == .reminder && reminder.operation == .create)
        #expect(reminder.field("dueDate")?.value == "2026-11-14T09:30:00+07:00")
        #expect(reminder.field("title")?.value == "Phòng khám Nha khoa An Bình")
        #expect(reminder.state == .awaitingApproval)
    }

    @Test func missingTitleLeavesTheLinkedStepNeedingInfo() async {
        let (engine, draft, _) = setUp(action: "calendarEvent")
        engine.edit(fieldId: "title", value: nil, stepId: draft.steps[0].id, in: draft)
        _ = await engine.confirm(stepId: draft.steps[0].id, in: draft)
        #expect(draft.steps[1].state == .needsInfo)
        #expect(draft.steps[1].field("title")?.source == .linked(stepId: draft.steps[0].id, fieldId: "title"))
    }

    @Test func copyContactInfoCopiesNameAndPhoneOnly() async {
        let system = MockSystemService()
        let (engine, draft, _) = setUp(action: "copyContactInfo", system: system)
        #expect(await engine.confirm(stepId: draft.steps[0].id, in: draft) == .finished(.succeeded))
        #expect(system.copied == ["Trần Văn Hùng\n0901 234 567"])
        #expect(draft.steps.count == 1)
    }

    @Test func copyWithoutNameOrPhoneCopiesNothing() async {
        let system = MockSystemService()
        let (engine, draft, _) = setUp(action: "copyContactInfo", system: system)
        engine.edit(fieldId: "personName", value: nil, stepId: draft.steps[0].id, in: draft)
        engine.edit(fieldId: "phoneNumber", value: nil, stepId: draft.steps[0].id, in: draft)
        _ = await engine.confirm(stepId: draft.steps[0].id, in: draft)
        #expect(system.copied.isEmpty)
    }

    @Test func reconfirmAfterEditUpdatesTheLinkInsteadOfAddingAStep() async {
        let (engine, draft, _) = setUp(action: "calendarEvent")
        let ocrId = draft.steps[0].id
        _ = await engine.confirm(stepId: ocrId, in: draft)
        // Edit the photo's title after "Tiếp tục": linked title follows, approval of both resets (D-101).
        #expect(engine.edit(fieldId: "title", value: "Khám răng", stepId: ocrId, in: draft))
        #expect(draft.steps[0].state == .awaitingApproval && draft.steps[0].operation == .create)
        #expect(draft.steps[1].field("title")?.value == "Khám răng")
        #expect(engine.confirmBlocker(stepId: draft.steps[1].id, in: draft) == .previousStep)
        #expect(await engine.confirm(stepId: ocrId, in: draft) == .finished(.succeeded))
        #expect(draft.steps.count == 2)
        #expect(engine.confirmBlocker(stepId: draft.steps[1].id, in: draft) == nil)
    }

    @Test func builderOnlyMakesCalendarAndReminderSteps() {
        var ocr = DraftBuilder.ocrStep(text: text, extract: .mock, now: now)
        for action in ["copyContactInfo", "ride"] {
            ocr.fields[ocr.fields.firstIndex { $0.id == "nextAction" }!].value = action
            #expect(DraftBuilder.linkedStep(from: ocr, order: 1, now: now) == nil)
        }
    }

    // MARK: - S04

    private func reviewModel(action: String?, system: MockSystemService = MockSystemService(),
                             tts: MockTTSService = MockTTSService()) -> (ReviewViewModel, TaskDraft) {
        let (engine, draft, repo) = setUp(action: action, system: system)
        let vm = ReviewViewModel(draftId: draft.id, repository: repo, engine: engine,
                                 permissions: MockPermissionManager(), system: system, tts: tts, now: { [now] in now })
        return (vm, draft)
    }

    // MARK: - 1D.7c "Đọc to" + "Chụp lại"

    @Test func readAloudOnlyOnThePhotoTextRow() async {
        let tts = MockTTSService()
        let (vm, _) = reviewModel(action: nil, tts: tts)
        let text = vm.step!.field("extractedText")!
        #expect(vm.canReadAloud(text))
        #expect(!vm.canReadAloud(vm.step!.field("title")!))
        await vm.toggleReading()
        #expect(tts.spoken.map(\.text) == [self.text] && tts.spoken.first?.rate == AppSettings().speechRate)
        #expect(!vm.isReading)                                                   // mock returns at once
    }

    @Test func readAloudHiddenAfterContinue() async {
        let (vm, _) = reviewModel(action: "copyContactInfo")
        await vm.confirm()
        #expect(!vm.canReadAloud(vm.step!.field("extractedText")!) && !vm.canRetake)
    }

    @Test func retakeCancelsTheReadingAndAsksForS09() {
        let (vm, draft) = reviewModel(action: "calendarEvent")
        #expect(vm.canRetake && !vm.didRetake)
        vm.retake()
        #expect(draft.steps[0].state == .cancelled && draft.steps.count == 1)    // nothing appended
        #expect(vm.didRetake)
    }

    @Test func retakeOnlyForTheOCRStep() async {
        let (vm, _) = reviewModel(action: "calendarEvent")
        await vm.confirm()                                                       // now on the calendar step
        #expect(vm.step?.kind == .calendarEvent && !vm.canRetake)
        vm.retake()
        #expect(!vm.didRetake)
    }

    @Test func reviewShowsContinueAndRadioWithoutRide() {
        let (vm, _) = reviewModel(action: nil)
        #expect(vm.confirmKey == "common.continue")
        #expect(vm.nextActionOptions == ["calendarEvent", "reminder", "copyContactInfo"])
        #expect(!vm.visibleFields.contains { $0.id == "nextAction" })            // own card, not a row
        vm.chooseNextAction("reminder")
        #expect(vm.nextActionValue == "reminder")
        vm.chooseNextAction("reminder")                                          // tap again = clear
        #expect(vm.nextActionValue == nil)
    }

    @Test func continueJumpsToTheAppendedStep() async {
        let (vm, draft) = reviewModel(action: "calendarEvent")
        await vm.confirm()
        #expect(vm.step?.id == draft.steps[1].id)
        #expect(vm.confirmKey == "common.confirm" && vm.nextActionOptions.isEmpty)
        #expect(vm.stepPosition?.current == 2 && vm.stepPosition?.total == 2)
    }

    @Test func copyShowsResultCardWithCopiedNote() async {
        let (vm, _) = reviewModel(action: "copyContactInfo")
        await vm.confirm()
        #expect(vm.step?.state == .succeeded)
        #expect(vm.resultCard?.detail == UserMessage(key: "common.copied").text)
        #expect(vm.resultCard?.primary?.action == .done)
    }
}

import Foundation
import Testing
@testable import EasyPhoneAI

/// 1D.7a — S09 → `/v1/extract` → `ocr.create` step → S04 (UI_SCREENS S09 step 3, DATA_MODEL §4, §1.7, API_CONTRACT §7.2).
@MainActor
@Suite("S09 extract → ocr step")
struct OCRExtractTests {
    /// = `OCRResult.sample.text` (59 UTF-16 units). `ExtractResponse.mock` spans title 0–27 and dateTime 38–59 fit;
    /// address / personName / phoneNumber point past the end (they belong to the longer contract text).
    let text = OCRResult.sample.text

    @Test func builderMapsFieldsSpansAndAction() {
        let step = DraftBuilder.ocrStep(text: text, extract: .mock, now: .now)
        #expect(step.kind == .ocr && step.operation == .create && step.state == .draft && step.order == 0)
        #expect(step.fields.map(\.id) == ["extractedText", "title", "dateTime", "address", "personName",
                                         "phoneNumber", "nextAction"])          // catalog order (§4)
        #expect(step.field("extractedText")?.value == text)
        #expect(step.field("extractedText")?.source == .device(origin: "ocr"))
        #expect(step.field("extractedText")?.required == true)
        let title = step.field("title")
        #expect(title?.value == "Phòng khám Nha khoa An Bình" && title?.confidence == 0.8)
        #expect(title?.source == .ocr(span: SourceSpan(start: 0, end: 27)))
        #expect(title?.needsReview == true)                                     // every OCR value is checked
        #expect(step.field("dateTime")?.source == .ocr(span: SourceSpan(start: 38, end: 59)))
        // Span outside the text → no `.ocr(span:)`, confidence capped at 0.5 (still needs review).
        let phone = step.field("phoneNumber")
        #expect(phone?.value == "0901 234 567" && phone?.source == .ai && phone?.confidence == 0.5)
        #expect(step.field("nextAction")?.value == "calendarEvent")
    }

    @Test func spansPointAtTheQuotedText() {
        let step = DraftBuilder.ocrStep(text: text, extract: .mock, now: .now)
        guard case .ocr(let span) = step.field("title")?.source else { Issue.record("no span"); return }
        let utf16 = Array(text.utf16)
        #expect(String(decoding: utf16[span.start..<span.end], as: UTF16.self) == "PHÒNG KHÁM NHA KHOA AN BÌNH")
    }

    @Test func rideAndEmptyResultGiveNoAction() {
        let ride = ExtractResponse(schemaVersion: 1, requestId: "r", fields: ExtractResponse.mock.fields,
                                   suggestedNextAction: "ride")                 // Phase 3 (D-142)
        #expect(DraftBuilder.ocrStep(text: text, extract: ride, now: .now).field("nextAction")?.value == nil)
        let none = DraftBuilder.ocrStep(text: text, extract: nil, now: .now)
        #expect(none.field("extractedText")?.value == text)
        #expect(none.fields.filter { $0.id != "extractedText" }.allSatisfy { $0.value == nil })
    }

    @Test func engineStoresTheStepOnceAwaitingApproval() {
        let repo = MockTaskRepository()
        let engine = TaskEngine(repository: repo)
        let draft = TaskDraft(inputMode: .photo, originalInput: text)
        #expect(engine.applyExtract(.mock, text: text, to: draft))
        #expect(draft.steps.count == 1 && draft.steps[0].state == .awaitingApproval)   // only extractedText required
        #expect(draft.serverRequestId == "req_01JC8Z7C10" && repo.draft(draft.id) != nil)
        #expect(!engine.applyExtract(.mock, text: text, to: draft))                 // never replaced
    }

    @Test func photoReadThenExtractOpensReview() async {
        let api = MockAPIClient()
        let repo = MockTaskRepository()
        let vm = OCRCaptureViewModel(permissions: MockPermissionManager(), cameraAvailable: false, repository: repo,
                                     api: api, engine: TaskEngine(repository: repo))
        await vm.received(Data([0xFF, 0xD8]), fromCamera: false)
        #expect(api.extractCalls.count == 1)
        let request = api.extractCalls[0].request
        #expect(request.ocrText == text && request.locale == "vi-VN" && request.schemaVersion == 1)
        let draft = vm.reviewDraftId.flatMap { repo.draft($0) }
        #expect(draft?.originalInput == text && draft?.steps.first?.kind == .ocr)
        #expect(draft?.steps.first?.field("title")?.value == "Phòng khám Nha khoa An Bình")
    }

    @Test func extractFailureStillOpensReviewWithTheText() async {
        let api = MockAPIClient(extract: .failure(.network(.offline)))
        let repo = MockTaskRepository()
        let vm = OCRCaptureViewModel(permissions: MockPermissionManager(), cameraAvailable: false, repository: repo,
                                     api: api, engine: TaskEngine(repository: repo))
        await vm.received(Data([0xFF, 0xD8]), fromCamera: false)
        let draft = vm.reviewDraftId.flatMap { repo.draft($0) }
        #expect(draft?.steps.first?.field("extractedText")?.value == text)              // nothing read is lost
        #expect(draft?.steps.first?.field("title")?.value == nil && draft?.serverRequestId == nil)
    }

    @Test func noTextNeverCallsExtract() async {
        let api = MockAPIClient()
        let vm = OCRCaptureViewModel(permissions: MockPermissionManager(), cameraAvailable: false,
                                     ocr: MockOCRService(.success(OCRResult(lines: [], source: .device))), api: api)
        await vm.received(Data([0xFF, 0xD8]), fromCamera: false)
        #expect(vm.mode == .noText && api.extractCalls.isEmpty && vm.reviewDraftId == nil)   // spec §6.3 AC5
    }

    @Test func requestCarriesNoLockedKey() throws {
        let request = ExtractRequest(ocrText: text, now: "2026-11-08T18:20:00+07:00", timezone: "Asia/Ho_Chi_Minh",
                                     locale: "vi-VN")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        #expect(Set(json?.keys.map { $0 } ?? []) == ["schemaVersion", "ocrText", "now", "timezone", "locale"])  // D-056
    }
}

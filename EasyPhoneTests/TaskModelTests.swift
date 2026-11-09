import Foundation
import SwiftData
import Testing
@testable import EasyPhoneAI

@Suite("Task models (DATA_MODEL §2–3)")
struct TaskModelTests {
    static let stepId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    static func sampleStep() -> TaskStep {
        TaskStep(
            id: stepId,
            order: 0,
            kind: .sms,
            operation: .open,
            state: .needsInfo,
            fields: [
                Field(id: "recipientName", type: .text, value: "Minh", required: true, source: .ai, confidence: 0.9,
                      ambiguity: Ambiguity(kind: .contact, question: "Bạn muốn nhắn Minh nào?", candidates: [
                          Candidate(id: "c1", title: "Minh (Công ty)", subtitle: "•••• 567", imageRef: "img1"),
                          Candidate(id: "c2", title: "Minh Anh"),
                      ])),
                Field(id: "contactId", type: .contactRef, required: true, source: .device(origin: "contacts"),
                      deviceOnly: true),
                Field(id: "body", type: .longText, value: "Con tới trễ 10 phút",
                      source: .ocr(span: SourceSpan(start: 0, end: 5, boundingBox: nil))),
            ],
            targetRef: nil,
            attempt: 1,
            stateChangedAt: Date(timeIntervalSince1970: 1_800_000_000),
            history: [StateChange(from: .draft, to: .needsInfo, event: .missingRequiredField,
                                  at: Date(timeIntervalSince1970: 1_800_000_000))]
        )
    }

    @Test func fieldJSONKeysMatchDataModel() throws {
        let field = Field(id: "title", type: .text, value: "Khám răng", required: true, source: .ai, confidence: 0.8)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(field)) as! [String: Any]
        #expect(Set(json.keys) == ["id", "type", "value", "required", "source", "confidence", "deviceOnly"])
        #expect(json["type"] as? String == "text")
        #expect((json["source"] as? [String: Any])?["type"] as? String == "ai")
    }

    @Test func stepRoundTripsThroughJSON() throws {
        let step = Self.sampleStep()
        let data = try JSONEncoder().encode(step)
        #expect(try JSONDecoder().decode(TaskStep.self, from: data) == step)
    }

    @Test func needsReviewRule() {
        var f = Field(id: "title", type: .text, value: "x", source: .ai)
        #expect(!f.needsReview)                                    // no confidence = 1
        f.confidence = 0.69
        #expect(f.needsReview)                                     // D-126
        f.confidence = 0.7
        #expect(!f.needsReview)
        f.source = .ocr(span: SourceSpan(start: 0, end: 1, boundingBox: nil))
        #expect(f.needsReview)                                     // OCR always reviewed
        f.source = .user
        f.ambiguity = Ambiguity(kind: .date, question: "Ngày nào?", candidates: [])
        #expect(f.needsReview)                                     // D-106
    }

    @Test func labelKeyFormat() {
        #expect(Field(id: "startDate", type: .dateTime).labelKey(kind: .calendarEvent) == "field.calendarEvent.startDate")
    }

    @Test func rawValues() {
        #expect(InputMode.allCases.map(\.rawValue) == ["text", "voice", "photo", "shortcut"])
        #expect(AmbiguityKind.allCases.map(\.rawValue) == ["contact", "date", "place", "phoneNumber", "other"])
    }

    @MainActor @Test func draftPersistsInSwiftData() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        let draft = TaskDraft(inputMode: .voice, originalInput: "Nhắn Minh con tới trễ", timeZoneId: "Asia/Ho_Chi_Minh",
                              steps: [Self.sampleStep()])
        context.insert(draft)
        try context.save()

        let id = draft.id
        let fresh = ModelContext(container)
        let fetched = try fresh.fetch(FetchDescriptor<TaskDraft>(predicate: #Predicate { $0.id == id }))
        #expect(fetched.count == 1)
        let loaded = try #require(fetched.first)
        #expect(loaded.schemaVersion == 1)
        #expect(loaded.inputMode == .voice)
        #expect(loaded.locale == "vi-VN")
        #expect(loaded.steps == [Self.sampleStep()])
    }
}

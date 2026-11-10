import Foundation
import Testing
@testable import EasyPhoneAI

@Suite("Task enums (DATA_MODEL §1)")
struct TaskEnumsTests {
    @Test func rawValuesMatchDataModel() {
        #expect(TaskKind.allCases.map(\.rawValue) ==
                ["calendarEvent", "reminder", "call", "sms", "place", "ocr", "emailReply", "ride", "food"])
        #expect(TaskOperation.allCases.map(\.rawValue) ==
                ["create", "update", "delete", "complete", "snooze", "open", "prepare"])
        #expect(TaskState.allCases.map(\.rawValue) ==
                ["draft", "needsInfo", "awaitingApproval", "processing", "prepared", "handedOff",
                 "succeeded", "unknown", "failed", "cancelled", "userMarkedDone"])
        #expect(TaskEvent.allCases.map(\.rawValue) ==
                ["missingRequiredField", "allRequiredFilled", "userConfirmed", "userEdited", "actionVerified",
                 "outcomeUnknownHandoff", "dataPrepared", "externalServiceOpened", "actionFailed", "interrupted",
                 "userMarkedDone", "userCancelled", "retry"])
        #expect(FieldType.allCases.map(\.rawValue) ==
                ["text", "longText", "dateTime", "date", "durationMinutes", "bool", "phone",
                 "contactRef", "placeRef", "address", "coordinate", "enumChoice"])
    }

    @Test func finalAndClosedStates() {
        let final = Set(TaskState.allCases.filter(\.isFinal))
        let closed = Set(TaskState.allCases.filter(\.isClosed))
        #expect(final == [.succeeded, .failed, .cancelled, .userMarkedDone])        // D-122
        #expect(closed == [.succeeded, .cancelled, .userMarkedDone])                // D-244
    }

    @Test func validKindOperationPairs() {
        let expected: [TaskKind: Set<TaskOperation>] = [
            .calendarEvent: [.create, .update, .delete],
            .reminder: [.create, .update, .delete, .complete, .snooze],
            .call: [.open], .sms: [.open], .place: [.create, .open],
            .ocr: [.create], .emailReply: [.create], .ride: [.prepare], .food: [.prepare],
        ]
        for kind in TaskKind.allCases {
            for op in TaskOperation.allCases {
                #expect(kind.allows(op) == expected[kind]!.contains(op), "\(kind)/\(op)")
            }
        }
    }

    @Test func unknownRawValueFailsDecoding() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([TaskKind].self, from: Data(#"["foo"]"#.utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([TaskState].self, from: Data(#"["done"]"#.utf8)) }
    }
}

@Suite("FieldSource JSON (DATA_MODEL §1.7)")
struct FieldSourceTests {
    private func json(_ s: FieldSource) throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return String(decoding: try e.encode(s), as: UTF8.self)
    }

    private func decode(_ s: String) throws -> FieldSource {
        try JSONDecoder().decode(FieldSource.self, from: Data(s.utf8))
    }

    @Test func everyCaseEncodesWithTypeDiscriminatorAndRoundTrips() throws {
        let id = UUID(uuidString: "6F1C2B7E-1D0A-4C55-9A51-2F6C1C0F9E11")!
        let cases: [(FieldSource, String)] = [
            (.user, #"{"type":"user"}"#),
            (.ai, #"{"type":"ai"}"#),
            (.ocr(span: SourceSpan(start: 3, end: 9, boundingBox: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25))),
             #"{"span":{"boundingBox":{"height":0.25,"width":0.5,"x":0.1,"y":0.2},"end":9,"start":3},"type":"ocr"}"#),
            (.ocr(span: SourceSpan(start: 0, end: 4, boundingBox: nil)), #"{"span":{"end":4,"start":0},"type":"ocr"}"#),
            (.device(origin: "contacts"), #"{"origin":"contacts","type":"device"}"#),
            (.linked(stepId: id, fieldId: "startDate"),
             #"{"fieldId":"startDate","stepId":"6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11","type":"linked"}"#),
            (.email(messageId: "m1"), #"{"messageId":"m1","type":"email"}"#),
        ]
        for (source, expected) in cases {
            #expect(try json(source) == expected)
            #expect(try decode(expected) == source)
        }
    }

    @Test func isOCROnlyForOCR() {
        #expect(FieldSource.ocr(span: SourceSpan(start: 0, end: 1, boundingBox: nil)).isOCR)
        #expect(!FieldSource.user.isOCR)
        #expect(!FieldSource.ai.isOCR)
    }

    @Test func badJSONFails() {
        #expect(throws: DecodingError.self) { try decode(#"{"type":"web"}"#) }
        #expect(throws: DecodingError.self) { try decode(#"{"origin":"contacts"}"#) }
        #expect(throws: DecodingError.self) { try decode(#"{"type":"ocr"}"#) }
        #expect(throws: DecodingError.self) { try decode(#"{"type":"linked","stepId":"x","fieldId":"a"}"#) }
    }
}

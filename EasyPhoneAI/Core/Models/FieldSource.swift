import Foundation

/// DATA_MODEL §1.7. JSON uses the discriminator key `type`: `{"type":"user"}`, `{"type":"ocr","span":{…}}`.
/// Rule: any user edit sets `source = .user` and `confidence = nil` (enforced where fields are edited).
enum FieldSource: Sendable, Hashable {
    case user                                   // typed or picked by the user
    case ai                                     // produced by /v1/parse
    case ocr(span: SourceSpan)                  // from /v1/extract over OCR text
    case device(origin: String)                 // "contacts", "calendar", "maps", "savedPlace"
    case linked(stepId: UUID, fieldId: String)  // copied from another step (DATA_MODEL §3.3)
    case email(messageId: String)               // Phase 2 — decoding only (D-150)

    var isOCR: Bool {
        if case .ocr = self { true } else { false }
    }
}

extension FieldSource: Codable {
    private enum CodingKeys: String, CodingKey { case type, span, origin, stepId, fieldId, messageId }
    private enum Kind: String, Codable { case user, ai, ocr, device, linked, email }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .user: self = .user
        case .ai: self = .ai
        case .ocr: self = .ocr(span: try c.decode(SourceSpan.self, forKey: .span))
        case .device: self = .device(origin: try c.decode(String.self, forKey: .origin))
        case .linked:
            self = .linked(stepId: try c.decode(UUID.self, forKey: .stepId),
                           fieldId: try c.decode(String.self, forKey: .fieldId))
        case .email: self = .email(messageId: try c.decode(String.self, forKey: .messageId))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user: try c.encode(Kind.user, forKey: .type)
        case .ai: try c.encode(Kind.ai, forKey: .type)
        case .ocr(let span):
            try c.encode(Kind.ocr, forKey: .type)
            try c.encode(span, forKey: .span)
        case .device(let origin):
            try c.encode(Kind.device, forKey: .type)
            try c.encode(origin, forKey: .origin)
        case .linked(let stepId, let fieldId):
            try c.encode(Kind.linked, forKey: .type)
            // DATA_MODEL §0 rule 4: UUIDs are lowercase strings on the wire.
            try c.encode(stepId.uuidString.lowercased(), forKey: .stepId)
            try c.encode(fieldId, forKey: .fieldId)
        case .email(let messageId):
            try c.encode(Kind.email, forKey: .type)
            try c.encode(messageId, forKey: .messageId)
        }
    }
}

/// DATA_MODEL §1.7. UTF-16 offsets into `TaskDraft.originalInput` (OCR text).
struct SourceSpan: Codable, Sendable, Hashable {
    var start: Int
    var end: Int
    var boundingBox: NormalizedRect?  // Vision box for "Xem ảnh gốc"
}

/// Vision-style normalized rectangle: 0–1, origin bottom-left (API_CONTRACT §7.2 `box`).
// TODO(spec): DATA_MODEL §1.7 uses `NormalizedRect` without defining its fields; x/y/width/height chosen.
struct NormalizedRect: Codable, Sendable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

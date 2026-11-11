import Foundation

// DATA_MODEL §4 + §4.1 (D-248). Single source, mirrored by `backend/app/schemas/field_catalog.json`:
// the JSON is exactly the `Codable` form of `FieldCatalog.mvp`, and `FieldCatalogTests` asserts they are equal.
// Change both in one commit.
// TODO(spec): DATA_MODEL §4 does not define the JSON layout; this file's `Codable` shape is used.

/// One field of a kind (DATA_MODEL §4 row).
struct FieldSpec: Codable, Sendable, Hashable {
    let id: String
    var type: FieldType
    /// 🔒 never sent to the backend, never listed to the LLM (D-056).
    var deviceOnly: Bool = false
    /// Built by the app, never produced by the LLM (e.g. `completed`, D-248).
    var appBuilt: Bool = false
    /// Allowed values for `enumChoice`.
    var options: [String]? = nil
    /// Operations this field belongs to; nil = every operation of the kind ("op=…" in §4).
    var operations: [TaskOperation]? = nil

    func applies(to operation: TaskOperation) -> Bool { operations?.contains(operation) ?? true }
}

/// A condition on the step's current field values (DATA_MODEL §4.1 "+ … when …").
enum RequirementCondition: Codable, Sendable, Hashable {
    /// `field.value == value`.
    case equals(field: String, value: String)
    /// `field.value` is not a phone number (D-253). Evaluated by the validator (1A.7) with phone normalization.
    case notPhoneNumber(field: String)

    private enum CodingKeys: String, CodingKey { case type, field, value }
    private enum Kind: String, Codable { case equals, notPhoneNumber }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let field = try c.decode(String.self, forKey: .field)
        switch try c.decode(Kind.self, forKey: .type) {
        case .equals: self = .equals(field: field, value: try c.decode(String.self, forKey: .value))
        case .notPhoneNumber: self = .notPhoneNumber(field: field)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .equals(field, value):
            try c.encode(Kind.equals, forKey: .type)
            try c.encode(field, forKey: .field)
            try c.encode(value, forKey: .value)
        case let .notPhoneNumber(field):
            try c.encode(Kind.notPhoneNumber, forKey: .type)
            try c.encode(field, forKey: .field)
        }
    }
}

/// Extra required fields when **all** conditions hold.
struct ConditionalRequirement: Codable, Sendable, Hashable {
    var when: [RequirementCondition]
    var fields: [String]
}

/// DATA_MODEL §4.1 row for one `(kind, operation)`.
struct RequiredRule: Codable, Sendable, Hashable {
    var operation: TaskOperation
    var requiresTargetRef: Bool = false
    var fields: [String]
    var conditional: [ConditionalRequirement] = []
}

/// All fields + required rules of one kind.
struct KindCatalog: Codable, Sendable, Hashable {
    var kind: TaskKind
    var fields: [FieldSpec]          // catalog order (§4) = `TaskStep.fields` order
    var required: [RequiredRule]     // one per allowed operation (§1.2)
}

struct FieldCatalog: Codable, Sendable, Hashable {
    var schemaVersion: Int
    var kinds: [KindCatalog]

    func kind(_ kind: TaskKind) -> KindCatalog? { kinds.first { $0.kind == kind } }

    /// Fields of `(kind, operation)` in catalog order.
    func fields(_ kind: TaskKind, _ operation: TaskOperation) -> [FieldSpec] {
        self.kind(kind)?.fields.filter { $0.applies(to: operation) } ?? []
    }

    /// The §4.1 rule; nil = `(kind, operation)` not in the catalog (invalid pair or Phase 2/3 kind).
    func rule(_ kind: TaskKind, _ operation: TaskOperation) -> RequiredRule? {
        self.kind(kind)?.required.first { $0.operation == operation }
    }
}

extension FieldCatalog {
    /// MVP kinds only. Phase 2/3 kinds are defined when their phase starts (DATA_MODEL §4, D-150).
    static let mvp = FieldCatalog(schemaVersion: 1, kinds: [
        KindCatalog(kind: .calendarEvent, fields: [
            FieldSpec(id: "title", type: .text),
            FieldSpec(id: "startDate", type: .dateTime),
            FieldSpec(id: "endDate", type: .dateTime),
            FieldSpec(id: "allDay", type: .bool),
            FieldSpec(id: "location", type: .address),
            FieldSpec(id: "notes", type: .longText),
            FieldSpec(id: "alertMinutesBefore", type: .durationMinutes),
            FieldSpec(id: "calendarId", type: .text, deviceOnly: true),
        ], required: [
            RequiredRule(operation: .create, fields: ["title", "startDate"]),
            RequiredRule(operation: .update, requiresTargetRef: true, fields: ["title", "startDate"]),
            RequiredRule(operation: .delete, requiresTargetRef: true, fields: []),
        ]),
        KindCatalog(kind: .reminder, fields: [
            FieldSpec(id: "title", type: .text),
            FieldSpec(id: "dueDate", type: .dateTime),
            FieldSpec(id: "notes", type: .longText),
            FieldSpec(id: "snoozeOption", type: .enumChoice,
                      options: ["min15", "hour1", "tomorrowMorning"], operations: [.snooze]),
            FieldSpec(id: "completed", type: .bool, appBuilt: true, operations: [.complete]),
        ], required: [
            RequiredRule(operation: .create, fields: ["title", "dueDate"]),
            RequiredRule(operation: .update, requiresTargetRef: true, fields: ["title", "dueDate"]),
            RequiredRule(operation: .delete, requiresTargetRef: true, fields: []),
            RequiredRule(operation: .complete, requiresTargetRef: true, fields: ["completed"]),
            RequiredRule(operation: .snooze, requiresTargetRef: true, fields: ["snoozeOption"]),
        ]),
        KindCatalog(kind: .call, fields: [
            FieldSpec(id: "recipientName", type: .text),
            FieldSpec(id: "contactId", type: .contactRef, deviceOnly: true),
            FieldSpec(id: "phoneNumber", type: .phone, deviceOnly: true),
        ], required: [
            RequiredRule(operation: .open, fields: ["recipientName", "phoneNumber"], conditional: [
                ConditionalRequirement(when: [.notPhoneNumber(field: "recipientName")], fields: ["contactId"]), // D-253
            ]),
        ]),
        KindCatalog(kind: .sms, fields: [
            FieldSpec(id: "recipientName", type: .text),
            FieldSpec(id: "contactId", type: .contactRef, deviceOnly: true),
            FieldSpec(id: "phoneNumber", type: .phone, deviceOnly: true),
            FieldSpec(id: "body", type: .longText),
            // TODO(spec): service ids from SupportedServices.json (DATA_MODEL §10, 1C.12) are also valid; only built-in `sms` listed.
            FieldSpec(id: "channel", type: .enumChoice, options: ["sms"]),
        ], required: [
            RequiredRule(operation: .open, fields: ["recipientName", "body", "channel"], conditional: [
                ConditionalRequirement(when: [.equals(field: "channel", value: "sms")],
                                       fields: ["phoneNumber"]),                                         // D-247
                ConditionalRequirement(when: [.equals(field: "channel", value: "sms"),
                                              .notPhoneNumber(field: "recipientName")],
                                       fields: ["contactId"]),                                           // D-253
                // D-297: Zalo opens the person's chat (`zalo.me/<phone>`), so it needs the contact + number again.
                ConditionalRequirement(when: [.equals(field: "channel", value: "zalo")],
                                       fields: ["phoneNumber"]),
                ConditionalRequirement(when: [.equals(field: "channel", value: "zalo"),
                                              .notPhoneNumber(field: "recipientName")],
                                       fields: ["contactId"]),
            ]),
        ]),
        KindCatalog(kind: .place, fields: [
            FieldSpec(id: "query", type: .text),
            FieldSpec(id: "name", type: .text),
            FieldSpec(id: "address", type: .address),
            FieldSpec(id: "coordinate", type: .coordinate),
            FieldSpec(id: "label", type: .enumChoice, options: ["home", "work", "custom"], operations: [.create]),
            FieldSpec(id: "customLabel", type: .text, operations: [.create]),
            FieldSpec(id: "mapsApp", type: .enumChoice, options: ["appleMaps", "googleMaps"], operations: [.open]),
        ], required: [
            RequiredRule(operation: .create, fields: ["query", "name", "address", "coordinate", "label"], conditional: [
                ConditionalRequirement(when: [.equals(field: "label", value: "custom")], fields: ["customLabel"]),
            ]),
            RequiredRule(operation: .open, fields: ["query", "name", "address", "coordinate", "mapsApp"]),
        ]),
        KindCatalog(kind: .ocr, fields: [
            FieldSpec(id: "extractedText", type: .longText),
            FieldSpec(id: "title", type: .text),                 // D-276
            FieldSpec(id: "dateTime", type: .dateTime),
            FieldSpec(id: "address", type: .address),
            FieldSpec(id: "personName", type: .text),
            FieldSpec(id: "phoneNumber", type: .phone),
            FieldSpec(id: "nextAction", type: .enumChoice,
                      options: ["calendarEvent", "reminder", "copyContactInfo", "ride"]),
        ], required: [
            RequiredRule(operation: .create, fields: ["extractedText"]),
        ]),
    ])
}

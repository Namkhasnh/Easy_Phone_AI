import Foundation
import Testing
@testable import EasyPhoneAI

@Suite("Field catalog (DATA_MODEL §4, §4.1)")
struct FieldCatalogTests {
    /// The backend file itself (shared source, DATA_MODEL §13). Simulator tests can read the repo on the Mac.
    static let jsonURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "backend/app/schemas/field_catalog.json")

    @Test func swiftEqualsBackendJSON() throws {
        let decoded = try JSONDecoder().decode(FieldCatalog.self, from: Data(contentsOf: Self.jsonURL))
        #expect(decoded == FieldCatalog.mvp)
        for kind in FieldCatalog.mvp.kinds {
            #expect(decoded.kind(kind.kind) == kind, "\(kind.kind)")
        }
    }

    @Test func mvpKindsOnly() {
        #expect(FieldCatalog.mvp.kinds.map(\.kind) == [.calendarEvent, .reminder, .call, .sms, .place, .ocr])
        for kind in [TaskKind.emailReply, .ride, .food] {
            #expect(FieldCatalog.mvp.kind(kind) == nil)                       // D-150
        }
    }

    @Test func oneRulePerAllowedOperation() {
        for entry in FieldCatalog.mvp.kinds {
            #expect(Set(entry.required.map(\.operation)) == entry.kind.allowedOperations, "\(entry.kind)")
            #expect(entry.required.count == entry.kind.allowedOperations.count, "\(entry.kind)")
        }
    }

    @Test func requiredIdsExistForTheirOperation() {
        for entry in FieldCatalog.mvp.kinds {
            #expect(Set(entry.fields.map(\.id)).count == entry.fields.count, "duplicate id in \(entry.kind)")
            for rule in entry.required {
                let ids = Set(FieldCatalog.mvp.fields(entry.kind, rule.operation).map(\.id))
                let needed = rule.fields + rule.conditional.flatMap(\.fields)
                for id in needed { #expect(ids.contains(id), "\(entry.kind).\(rule.operation) \(id)") }
            }
        }
    }

    @Test func dataModelSection41() {
        let c = FieldCatalog.mvp
        #expect(c.rule(.calendarEvent, .delete) == RequiredRule(operation: .delete, requiresTargetRef: true, fields: []))
        #expect(c.rule(.calendarEvent, .create)?.requiresTargetRef == false)
        #expect(c.rule(.reminder, .complete)?.fields == ["completed"])
        #expect(c.rule(.reminder, .snooze)?.fields == ["snoozeOption"])
        #expect(c.rule(.sms, .open)?.fields == ["recipientName", "body", "channel"])  // D-247: 🔒 ids only when channel = sms
        #expect(c.rule(.call, .open)?.conditional.first?.fields == ["contactId"])    // D-253
        #expect(c.rule(.call, .create) == nil)                                        // invalid pair
        #expect(c.fields(.reminder, .create).map(\.id) == ["title", "dueDate", "notes"])
        #expect(c.fields(.place, .open).map(\.id) == ["query", "name", "address", "coordinate", "mapsApp"])
    }

    @Test func lockedAndAppBuiltFields() {
        var locked: Set<String> = []
        var built: Set<String> = []
        for entry in FieldCatalog.mvp.kinds {
            for f in entry.fields {
                if f.deviceOnly { locked.insert("\(entry.kind.rawValue).\(f.id)") }
                if f.appBuilt { built.insert("\(entry.kind.rawValue).\(f.id)") }
                #expect((f.type == .enumChoice) == (f.options != nil), "\(entry.kind).\(f.id)")
            }
        }
        #expect(locked == ["calendarEvent.calendarId", "call.contactId", "call.phoneNumber",
                           "sms.contactId", "sms.phoneNumber"])                     // D-056
        #expect(built == ["reminder.completed"])                                    // D-248
    }

    @Test func conditionJSONShape() throws {
        let data = try JSONEncoder().encode(RequirementCondition.equals(field: "channel", value: "sms"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
        #expect(json == ["type": "equals", "field": "channel", "value": "sms"])
        let back = try JSONDecoder().decode(RequirementCondition.self,
                                            from: Data(#"{"type":"notPhoneNumber","field":"recipientName"}"#.utf8))
        #expect(back == .notPhoneNumber(field: "recipientName"))
    }
}

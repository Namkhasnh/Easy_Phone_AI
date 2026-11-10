import Foundation
import Testing
@testable import EasyPhoneAI

/// 1A.6 — DATA_MODEL §3.4 + §13 "Hash changes when any field changes; stable across field order".
@Suite("ApprovalHash (DATA_MODEL §3.4)")
struct ApprovalHashTests {
    static func step(fields: [Field]? = nil, targetRef: String? = nil) -> TaskStep {
        TaskStep(
            order: 0,
            kind: .calendarEvent,
            operation: .create,
            fields: fields ?? [
                Field(id: "title", type: .text, value: "Khám răng"),
                Field(id: "startDate", type: .dateTime, value: "2026-11-09T14:00:00+07:00"),
            ],
            targetRef: targetRef
        )
    }

    @Test func canonicalFormVerbatim() {
        #expect(ApprovalHash.canonical(Self.step())
            == "calendarEvent|create|\nstartDate=2026-11-09T14:00:00+07:00\ntitle=Khám răng")
        let empty = Self.step(fields: [Field(id: "notes", type: .longText)], targetRef: "ek-1")
        #expect(ApprovalHash.canonical(empty) == "calendarEvent|create|ek-1\nnotes=")
    }

    @Test func knownVector() {
        // printf 'calendarEvent|create|\nstartDate=2026-11-09T14:00:00+07:00\ntitle=Khám răng' | shasum -a 256
        #expect(ApprovalHash.hash(Self.step())
            == "d545c5bed882272c7d3746c45ffd30649e0b33b5956420baa5ee16d62f8839a7")
    }

    @Test func stableAcrossFieldOrder() {
        let a = Self.step()
        let b = Self.step(fields: a.fields.reversed())
        #expect(ApprovalHash.hash(a) == ApprovalHash.hash(b))
    }

    @Test func ignoresNonContentProperties() {
        var b = Self.step()
        let a = b
        b.state = .awaitingApproval
        b.attempt = 3
        b.fields[0].source = .ai
        b.fields[0].confidence = 0.4
        #expect(ApprovalHash.hash(a) == ApprovalHash.hash(b))
    }

    @Test func changesOnAnyFieldEdit() {
        let base = ApprovalHash.hash(Self.step())
        for i in Self.step().fields.indices {
            var edited = Self.step()
            edited.fields[i].value! += "x"
            #expect(ApprovalHash.hash(edited) != base)
            edited.fields[i].value = nil
            #expect(ApprovalHash.hash(edited) != base)
        }
    }

    @Test func changesOnDeviceOnlyFieldAndTargetRef() {
        let withContact = Self.step(fields: [Field(id: "contactId", type: .contactRef, value: "A", deviceOnly: true)])
        var other = withContact
        other.fields[0].value = "B"
        #expect(ApprovalHash.hash(withContact) != ApprovalHash.hash(other))   // 🔒 fields included

        #expect(ApprovalHash.hash(Self.step(targetRef: "ek-1")) != ApprovalHash.hash(Self.step(targetRef: "ek-2")))
        #expect(ApprovalHash.hash(Self.step(targetRef: "ek-1")) != ApprovalHash.hash(Self.step()))
    }

    @Test func changesOnKindOrOperation() {
        var update = Self.step()
        update.operation = .update
        #expect(ApprovalHash.hash(update) != ApprovalHash.hash(Self.step()))
    }

    @Test func formatIsLowercaseHex64() {
        let h = ApprovalHash.hash(Self.step())
        #expect(h.count == 64)
        #expect(h.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func matchesOnlyStoredUnchangedHash() {
        var s = Self.step()
        #expect(!ApprovalHash.matches(s))                        // no hash → not approved
        s.approvedSnapshotHash = ApprovalHash.hash(s)
        #expect(ApprovalHash.matches(s))
        s.fields[0].value = "Khám mắt"                           // edit after approval (D-101)
        #expect(!ApprovalHash.matches(s))
    }
}

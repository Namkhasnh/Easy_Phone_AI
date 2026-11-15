import Foundation
import Testing
@testable import EasyPhoneAI

/// 1C.16 — ARCHITECTURE §5.4, D-125, D-243, DATA_MODEL §3.5: `processing` → `interrupted` → `unknown` on launch, then
/// evidence lookup → `succeeded` or stays `unknown`; `unknown` + retry never creates a second item (D-105).
@MainActor
@Suite("LaunchVerifier (ARCHITECTURE §5.4)")
struct LaunchVerifierTests {
    static let now = Validator.parseDateTime("2026-11-10T09:00:00+07:00")!
    static let start = "2026-11-13T14:00:00+07:00"

    let repo = MockTaskRepository()
    let calendar = MockCalendarService()
    let permissions = MockPermissionManager()
    let localData = MockLocalDataRepository()
    let engine: TaskEngine
    let verifier: LaunchVerifier

    init() {
        engine = TaskEngine(repository: repo,
                            executors: [.calendarEvent: CalendarExecutor(calendar: calendar, permissions: permissions),
                                        .call: CallExecutor(calls: MockCallService()),
                                        .place: PlaceExecutor(places: MockPlacesService(), localData: localData)],
                            now: { Self.now })
        verifier = LaunchVerifier(repository: repo, engine: engine)
    }

    func stored(_ kind: TaskKind, _ op: TaskOperation, state: TaskState, values: [String: String] = [:],
                targetRef: String? = nil) -> TaskDraft {
        let fields = FieldCatalog.mvp.fields(kind, op).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, deviceOnly: $0.deviceOnly)
        }
        let step = TaskStep(order: 0, kind: kind, operation: op, state: state, fields: fields, targetRef: targetRef,
                            attempt: 1)
        let d = TaskDraft(inputMode: .text, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh", steps: [step])
        repo.save(d)
        return d
    }

    static let dentist = ["title": "Khám răng", "startDate": start]

    @Test func killedAfterCalendarSaveIsVerifiedByStepTag() async throws {
        let d = stored(.calendarEvent, .create, state: .processing, values: Self.dentist)
        let input = try #require(CalendarExecutor.input(from: d.steps[0]))
        let id = try await calendar.save(input, stepTag: StepTag.make(d.steps[0].id), existing: nil)   // saved, then killed

        await verifier.runOnce()
        #expect(d.steps[0].state == .succeeded)
        #expect(d.steps[0].resultEvidence == CalendarExecutor.evidence(id))
        #expect(d.steps[0].history.map(\.event) == [.interrupted, .actionVerified])
    }

    @Test func killedBeforeSaveStaysUnknownAndRetryCreatesOnce() async {
        let d = stored(.calendarEvent, .create, state: .processing, values: Self.dentist)
        await verifier.runOnce()
        #expect(d.steps[0].state == .unknown)
        #expect(d.steps[0].resultEvidence == nil)

        #expect(engine.retry(stepId: d.steps[0].id, in: d))                  // D-243: unknown → awaitingApproval
        #expect(d.steps[0].state == .awaitingApproval)
        #expect(await engine.confirm(stepId: d.steps[0].id, in: d) == .finished(.succeeded))
        #expect(calendar.saveCount == 1)
    }

    @Test func unknownDeleteIsVerifiedWhenTargetIsGone() async {
        let d = stored(.calendarEvent, .delete, state: .unknown, targetRef: "gone-1")
        await verifier.runOnce()
        #expect(d.steps[0].state == .succeeded)
        #expect(d.steps[0].resultEvidence == "ek:deleted:gone-1")
    }

    @Test func writeOnlyCalendarCannotVerify() async throws {
        permissions.set(.calendar, .writeOnly)
        let d = stored(.calendarEvent, .create, state: .unknown, values: Self.dentist)
        let input = try #require(CalendarExecutor.input(from: d.steps[0]))
        _ = try await calendar.save(input, stepTag: StepTag.make(d.steps[0].id), existing: nil)
        await verifier.runOnce()
        #expect(d.steps[0].state == .unknown)
    }

    @Test func interruptedCallStaysUnknownNeverSucceeded() async {
        let d = stored(.call, .open, state: .processing, values: ["recipientName": "anh Minh"])
        await verifier.runOnce()
        #expect(d.steps[0].state == .unknown)                                // D-102: tel:// never succeeded
    }

    @Test func savedPlaceIsVerified() async {
        let d = stored(.place, .create, state: .unknown, values: ["name": "Nhà", "label": "home"])
        localData.save(SavedPlace(id: d.steps[0].id, label: "home", customLabel: nil, name: "Nhà", address: "1 Lê Lợi",
                                  latitude: 10.77, longitude: 106.70))
        await verifier.runOnce()
        #expect(d.steps[0].state == .succeeded)
        #expect(d.steps[0].resultEvidence == PlaceExecutor.evidence(d.steps[0].id))
    }

    @Test func runsOncePerProcess() async {
        await verifier.runOnce()
        let d = stored(.call, .open, state: .processing)                    // started after launch
        await verifier.runOnce()
        #expect(d.steps[0].state == .processing)
    }
}

import Testing
@testable import EasyPhoneAI

/// Smoke tests for 1A.4. The exhaustive table + every illegal pair is 1A.5 (DATA_MODEL §13).
@Suite("TaskStateMachine (DATA_MODEL §1.5)")
struct TaskStateMachineTests {
    typealias SM = TaskStateMachine

    @Test func happyPathCreate() {
        #expect(SM.transition(.draft, .missingRequiredField) == .needsInfo)
        #expect(SM.transition(.needsInfo, .allRequiredFilled) == .awaitingApproval)
        #expect(SM.transition(.awaitingApproval, .userConfirmed) == .processing)
        #expect(SM.transition(.processing, .actionVerified) == .succeeded)
    }

    @Test func smsComposerCancelReturnsToApproval() {                 // D-222
        #expect(SM.transition(.processing, .userCancelled, context: .init(composerDismissed: true)) == .awaitingApproval)
        #expect(SM.transition(.processing, .userCancelled) == .cancelled)
    }

    @Test func failedAndUnknownRows() {                                // D-243
        #expect(SM.transition(.failed, .retry) == .awaitingApproval)
        #expect(SM.transition(.failed, .userCancelled) == .cancelled)
        #expect(SM.transition(.failed, .userMarkedDone) == .userMarkedDone)
        #expect(SM.transition(.unknown, .retry) == .awaitingApproval)
        #expect(SM.transition(.prepared, .userMarkedDone) == .userMarkedDone)   // D-242
    }

    @Test func illegalPairsReturnNil() {
        #expect(SM.transition(.draft, .userConfirmed) == nil)          // never act without confirmation (D-100)
        #expect(SM.transition(.succeeded, .userCancelled) == nil)      // final
        #expect(SM.transition(.handedOff, .actionVerified) == nil)     // D-102: hand-off never succeeded
        #expect(SM.transition(.cancelled, .retry) == nil)
    }
}

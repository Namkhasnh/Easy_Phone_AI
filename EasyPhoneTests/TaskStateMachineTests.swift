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

    /// DATA_MODEL §1.5, copied row by row (independent of the implementation's `switch`).
    struct Key: Hashable { let state: TaskState; let event: TaskEvent; let composerDismissed: Bool }

    static let expectedTable: [Key: TaskState] = {
        var t: [Key: TaskState] = [:]
        func row(_ from: [TaskState], _ event: TaskEvent, _ to: TaskState, composer: [Bool] = [false, true]) {
            for s in from { for c in composer { t[Key(state: s, event: event, composerDismissed: c)] = to } }
        }
        row([.draft], .missingRequiredField, .needsInfo)
        row([.draft, .needsInfo], .allRequiredFilled, .awaitingApproval)
        row([.needsInfo], .userEdited, .needsInfo)
        row([.awaitingApproval], .userConfirmed, .processing)
        row([.awaitingApproval], .userEdited, .awaitingApproval)
        row([.awaitingApproval], .missingRequiredField, .needsInfo)
        row([.processing], .actionVerified, .succeeded)
        row([.processing], .outcomeUnknownHandoff, .handedOff)
        row([.processing], .dataPrepared, .prepared)
        row([.prepared], .externalServiceOpened, .handedOff)
        row([.processing], .actionFailed, .failed)
        row([.processing], .interrupted, .unknown)
        row([.unknown], .actionVerified, .succeeded)
        row([.unknown], .retry, .awaitingApproval)                              // D-243
        row([.handedOff, .unknown], .userMarkedDone, .userMarkedDone)
        row([.prepared], .userMarkedDone, .userMarkedDone)                      // D-242
        row([.failed], .retry, .awaitingApproval)                               // D-105
        row([.failed], .userCancelled, .cancelled)                              // D-243
        row([.failed], .userMarkedDone, .userMarkedDone)                        // D-243
        row([.succeeded], .userEdited, .awaitingApproval)
        // "any non-final + userCancelled → cancelled"
        row([.draft, .needsInfo, .awaitingApproval, .prepared, .handedOff, .unknown], .userCancelled, .cancelled)
        row([.processing], .userCancelled, .cancelled, composer: [false])
        row([.processing], .userCancelled, .awaitingApproval, composer: [true]) // D-222
        return t
    }()

    @Test func everyPairMatchesTheTable() {
        var checked = 0
        for state in TaskState.allCases {
            for event in TaskEvent.allCases {
                for composer in [false, true] {
                    let expected = Self.expectedTable[Key(state: state, event: event, composerDismissed: composer)]
                    let actual = SM.transition(state, event, context: TransitionContext(composerDismissed: composer))
                    #expect(actual == expected, "\(state) + \(event) composerDismissed=\(composer)")
                    checked += 1
                }
            }
        }
        #expect(checked == 11 * 13 * 2)
    }

    @Test func tableSize() {
        // 18 one-state rows + 2 two-state rows (4 pairs) + 7 non-final cancels (incl. processing) = 29 pairs, ×2 contexts.
        #expect(Self.expectedTable.count == (18 + 4 + 7) * 2)
    }

    @Test func finalStatesOnlyLeaveByListedRows() {
        // D-122: closed states never move except succeeded + userEdited (new update action).
        for event in TaskEvent.allCases {
            #expect(SM.transition(.cancelled, event) == nil, "cancelled + \(event)")
            #expect(SM.transition(.userMarkedDone, event) == nil, "userMarkedDone + \(event)")
            if event != .userEdited { #expect(SM.transition(.succeeded, event) == nil, "succeeded + \(event)") }
        }
    }

    @Test func illegalPairsReturnNil() {
        #expect(SM.transition(.draft, .userConfirmed) == nil)          // never act without confirmation (D-100)
        #expect(SM.transition(.succeeded, .userCancelled) == nil)      // final
        #expect(SM.transition(.handedOff, .actionVerified) == nil)     // D-102: hand-off never succeeded
        #expect(SM.transition(.cancelled, .retry) == nil)
    }
}

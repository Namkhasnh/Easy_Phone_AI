import Foundation
import Testing
@testable import EasyPhoneAI

@Suite("AppState entitlement cache (D-085)")
@MainActor
struct AppStateTests {
    private let now = Date(timeIntervalSince1970: 1_762_600_000)

    @Test func meCreatesEntitlement() {
        let state = AppState()
        state.apply(me: .mock, now: now)
        #expect(state.entitlement == CachedEntitlement(plan: .free, quotaRemaining: 7,
                                                       resetsAt: MeResponse.mock.quota.resetsAt, fetchedAt: now))
    }

    @Test func quotaUpdatesExistingEntitlement() {
        let state = AppState()
        state.apply(me: .mock, now: now)
        let later = now.addingTimeInterval(60)
        let resets = now.addingTimeInterval(86_400)
        state.apply(quota: Quota(limit: 10, used: 4, remaining: 6, resetsAt: resets), now: later)
        #expect(state.entitlement == CachedEntitlement(plan: .free, quotaRemaining: 6, resetsAt: resets, fetchedAt: later))
    }

    @Test func quotaWithoutMeIsIgnored() {
        let state = AppState()
        state.apply(quota: Quota(limit: 10, used: 4, remaining: 6, resetsAt: now), now: now)
        #expect(state.entitlement == nil)
    }
}

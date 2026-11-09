import Foundation
import Observation

/// Shared app-wide state (ARCHITECTURE §2.2). `@MainActor` per §8.
@Observable @MainActor final class AppState {
    var session: SessionState = .restoring
    var entitlement: CachedEntitlement?      // display only (D-085)
    var startListeningRequested = false      // set by StartListeningIntent / easyphone://listen / widgets (D-172)
    var blockingScreen: BlockingScreen?      // .clientOutdated(minVersion) on 426

    init() {}

    /// After `GET /v1/me` (API_CONTRACT §6.2). In memory only until `AppSettings` exists (1A.9).
    func apply(me: MeResponse, now: Date = .now) {
        entitlement = CachedEntitlement(plan: me.plan, quotaRemaining: me.quota.remaining,
                                        resetsAt: me.quota.resetsAt, fetchedAt: now)
    }

    /// After any response with `X-Quota-*` (API_CONTRACT §4.5). Headers carry no plan, so this waits for `/v1/me`.
    func apply(quota: Quota, now: Date = .now) {
        guard var current = entitlement else { return }
        current.quotaRemaining = quota.remaining
        current.resetsAt = quota.resetsAt
        current.fetchedAt = now
        entitlement = current
    }
}

enum SessionState: Sendable, Hashable {
    case signedOut
    case signedIn(userId: UUID)   // Supabase auth user id (`sub`)
    case restoring
}

enum BlockingScreen: Sendable, Hashable {
    case clientOutdated(minVersion: String)   // S19, API_CONTRACT 426
}

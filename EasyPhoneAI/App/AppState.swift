import Foundation
import Observation

/// Shared app-wide state (ARCHITECTURE §2.2). `@MainActor` per §8.
@Observable @MainActor final class AppState {
    var session: SessionState = .restoring
    var entitlement: CachedEntitlement?      // display only (D-085)
    var startListeningRequested = false      // set by StartListeningIntent / easyphone://listen / widgets (D-172)
    var blockingScreen: BlockingScreen?      // .clientOutdated(minVersion) on 426

    init() {}
}

enum SessionState: Sendable, Hashable {
    case signedOut
    case signedIn(userId: UUID)   // Supabase auth user id (`sub`)
    case restoring
}

enum BlockingScreen: Sendable, Hashable {
    case clientOutdated(minVersion: String)   // S19, API_CONTRACT 426
}

import Foundation
import Observation

/// ARCHITECTURE §2.2. `calendarToday` / `reminders`: D-266 (S11, S12).
enum Route: Hashable, Sendable {
    case review(UUID)
    case ocr
    case history
    case settings
    case paywall
    case places
    case conversation(UUID?)
    case calendarToday
    case reminders
}

/// Owns the single `NavigationStack(path:)`. Reopen at the exact step = `.review(draftId)` (spec §6.10 AC2).
@Observable @MainActor final class Router {
    var path: [Route] = []

    init() {}

    func push(_ route: Route) {
        path.append(route)
    }

    func popToRoot() {
        path.removeAll()
    }
}

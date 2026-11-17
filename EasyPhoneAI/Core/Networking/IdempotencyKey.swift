import Foundation

/// ARCHITECTURE §10.1. Created by the ViewModel for each endpoint call of a user action (D-230, D-245);
/// reused only by the automatic retries of that same call. "Thử lại" or a relaunch = a new key.
struct IdempotencyKey: Sendable, Hashable {
    let value: String

    /// A new key for one endpoint call of a user action (D-245).
    init() { value = UUID().uuidString.lowercased() }

    /// The step's own key (`/v1/gmail/drafts`, D-105): every retry of that step finds the draft it already made.
    init(step id: UUID) { value = id.uuidString.lowercased() }
}

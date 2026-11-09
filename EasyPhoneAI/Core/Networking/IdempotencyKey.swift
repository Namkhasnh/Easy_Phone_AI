import Foundation

/// ARCHITECTURE §10.1. Created by the ViewModel for each endpoint call of a user action (D-230, D-245);
/// reused only by the automatic retries of that same call. "Thử lại" or a relaunch = a new key.
struct IdempotencyKey: Sendable, Hashable {
    let value: String = UUID().uuidString.lowercased()
}

import ActivityKit
import Foundation

/// 4H.5 (D-337, D-325): the Live Activity "Bước 3/7" on the Lock Screen / Dynamic Island while the user follows a guide
/// in another app. Compiled into the app (starts / updates / ends it) **and** the widget extension (draws it).
/// Local updates only: no push (a free Apple ID has no push entitlement, D-282). Text is already in Vietnamese.
struct GuideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// "Bước 3/7" (app string `guide.step`).
        var label: String
        var text: String
        var step: Int
        var total: Int
    }

    var title: String
}

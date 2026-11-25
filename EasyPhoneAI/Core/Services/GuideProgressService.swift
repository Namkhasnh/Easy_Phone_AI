import Foundation

/// What the Live Activity shows for one guide step (4H.5).
struct GuideProgress: Sendable, Hashable {
    var title: String
    var label: String
    var text: String
    var step: Int
    var total: Int
}

/// 4H.5: the guide's current step outside the app (Live Activity "Bước 3/7"). Best effort: Live Activities off, or not
/// allowed for this signing (D-282) → nothing is shown and nothing fails; the panel and S23 still work.
protocol GuideProgressService: Sendable {
    @MainActor func show(_ progress: GuideProgress)
    @MainActor func end()
}

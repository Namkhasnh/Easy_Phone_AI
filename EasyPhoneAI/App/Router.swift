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
    /// D-294: S11 for one day (`YYYY-MM-DD`), from "xem lịch ngày mai".
    case calendarDay(String)
    case reminders
    /// S21 Mail summary (Phase 2, D-304), from "có thư mới không" (`unsupported.reason = checkMail`).
    /// `codesOnly`: "xem mã gửi về" shows only verification codes (owner 2026-11-18, D-311), no other mail, no AI.
    case mail(codesOnly: Bool)
    /// S21 "Trả lời" (2.6b): S03 listening for the reply content; the step gets the thread + address from `context`.
    case mailReply(MailReplyContext)
    /// S22 "Ngày giỗ & lễ" (4L.6, D-331).
    case lunarDays
    /// S23 "Khoai hướng dẫn" (4H.3, D-337) from a "làm sao …" question; `spoken` = hands-free "tiếp" (D-312).
    case guide(question: String, spoken: Bool)
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

    /// Replaces the top screen (S03 → S04 when the draft is ready), so "Back" from Review does not reopen S03.
    func replaceLast(with route: Route) {
        if !path.isEmpty { path.removeLast() }
        path.append(route)
    }
}

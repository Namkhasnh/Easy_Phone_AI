import Foundation
import Observation

/// S02 Home (UI_SCREENS S02, §4; spec §6.10 AC5; D-244, P-36, P-40, D-289).
@Observable @MainActor final class HomeViewModel {
    /// Quick-link tiles (UI_SCREENS S02). Simple mode keeps only "Lịch hôm nay" (P-40).
    enum QuickLink: String, CaseIterable, Identifiable, Sendable {
        case calendar, reminders, places
        var id: String { rawValue }
        var titleKey: String { "home.link.\(rawValue)" }
        var route: Route {
            switch self {
            case .calendar: .calendarToday
            case .reminders: .reminders
            case .places: .places
            }
        }
        // TODO(spec): UI_SCREENS S02 names no quick-link icons; SF Symbols chosen here.
        var symbol: String {
            switch self {
            case .calendar: "calendar"
            case .reminders: "checklist"
            case .places: "mappin.and.ellipse"
            }
        }
    }

    /// "Việc chưa xong": at most 3 rows (UI_SCREENS S02).
    static let unfinishedLimit = 3
    // TODO(spec): UI_SCREENS S02 gives no threshold for `home.quota.low`; shown at ≤ 2 units left (owner OK 2026-11-10, DOC-28).
    static let quotaLowThreshold = 2

    var inputText = ""
    let settings: AppSettings
    private(set) var unfinished: [DraftRow] = []
    private(set) var hasAnyDraft = false

    private let repository: any TaskRepository
    private let now: () -> Date
    private let rowBuilder: DraftRowBuilder

    init(repository: any TaskRepository, localData: any LocalDataRepository,
         now: @escaping () -> Date = { .now }, timeZone: TimeZone = .current) {
        self.repository = repository
        self.now = now
        settings = localData.settings()
        rowBuilder = DraftRowBuilder(now: now, timeZone: timeZone)
    }

    /// "Gửi" appears only when the text is non-empty (UI_SCREENS S02).
    var canSend: Bool { !trimmedInput.isEmpty }

    var quickLinks: [QuickLink] { settings.simpleMode ? [.calendar] : QuickLink.allCases }

    var showsMascot: Bool { settings.petEnabled }

    // TODO(spec): AppSettings has no "first run" flag (P-36); the tip shows while the phone has no drafts at all (owner OK 2026-11-10, DOC-28).
    var showsFirstRunTip: Bool { !hasAnyDraft }

    /// `home.quota.low` text, or `nil`. Display only (D-085): the backend decides entitlement.
    func quotaLowMessage(_ entitlement: CachedEntitlement?) -> UserMessage? {
        guard let remaining = entitlement?.quotaRemaining, remaining <= Self.quotaLowThreshold else { return nil }
        return UserMessage(key: "home.quota.low", args: ["\(remaining)"])
    }

    /// Drafts in "Cần bạn làm tiếp" or "Đang chờ" (D-244), newest first, max 3.
    func load() {
        let groups: [HistoryGroup] = [.needsYou, .waiting]
        let drafts = groups.flatMap { repository.history(group: $0) }.sorted { $0.updatedAt > $1.updatedAt }
        unfinished = Array(drafts.compactMap(rowBuilder.row).prefix(Self.unfinishedLimit))
        hasAnyDraft = HistoryGroup.allCases.contains { !repository.history(group: $0).isEmpty }
    }

    /// "Gửi": saves the typed request as a new draft first (D-104: never lose input), clears the field and
    /// returns the draft id for S03 (`Route.conversation(id)`); parsing happens there (1B.4).
    func send() -> UUID? {
        let text = trimmedInput
        guard !text.isEmpty else { return nil }
        let draft = TaskDraft(createdAt: now(), inputMode: .text, originalInput: text)
        repository.save(draft)
        inputText = ""
        hasAnyDraft = true
        return draft.id
    }

    private var trimmedInput: String { inputText.trimmingCharacters(in: .whitespacesAndNewlines) }
}

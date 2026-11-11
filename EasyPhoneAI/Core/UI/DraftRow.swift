import Foundation

/// One draft as a list row: S14 History rows and the S02 "Việc chưa xong" rows (UI_SCREENS S02, S14, D-244).
struct DraftRow: Identifiable, Hashable {
    let id: UUID                 // draft id → `Route.review(id)` opens it at `currentStep` (spec §6.10 AC2)
    let symbol: String
    let summary: String
    let time: String
    let badgeState: TaskState
    let badgeArgs: [String]
    let stepsText: String?       // "{done}/{total} bước" for multi-step drafts
}

/// Builds `DraftRow`s. Shared by `HistoryViewModel` and `HomeViewModel` so both lists read the same.
struct DraftRowBuilder {
    private let now: () -> Date
    private let calendar: Calendar

    init(now: @escaping () -> Date = { .now }, timeZone: TimeZone = .current) {
        self.now = now
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        calendar = cal
    }

    /// `nil` for a draft with no steps (nothing to open yet).
    func row(_ draft: TaskDraft) -> DraftRow? {
        guard let current = draft.currentStep else { return nil }
        // "StateBadge of the draft's group step": the first step (by order) whose group is the draft's group.
        let groupStep = draft.steps.sorted { $0.order < $1.order }
            .first { $0.state.historyGroup == draft.overallStatus } ?? current
        let summary = Self.summary(current)
        return DraftRow(id: draft.id, symbol: Self.symbol(current.kind), summary: summary,
                        time: relativeTime(draft.updatedAt), badgeState: groupStep.state,
                        badgeArgs: StateBadge.labelArgs(groupStep),
                        stepsText: draft.steps.count > 1
                            ? UserMessage(key: "history.steps", args: ["\(draft.closedStepCount)", "\(draft.steps.count)"]).text
                            : nil)
    }

    // TODO(spec): UI_SCREENS S14 names no kind icons; SF Symbols chosen here.
    static func symbol(_ kind: TaskKind) -> String {
        switch kind {
        case .calendarEvent: "calendar"
        case .reminder: "bell"
        case .call: "phone"
        case .sms: "message"
        case .place: "mappin.and.ellipse"
        case .ocr: "doc.text.viewfinder"
        case .emailReply: "envelope"
        case .ride: "car"
        case .food: "takeoutbag.and.cup.and.straw"
        }
    }

    // TODO(spec): `{mainValue}` of `history.summary` is only shown by example ("anh Minh"); per-kind field chosen here.
    /// "{step title}: {main value}" (`history.summary`), or the step title alone. Also the S08 body (D-242).
    static func summary(_ step: TaskStep) -> String {
        let stepTitle = UserMessage(key: "step.\(step.kind.rawValue).\(step.operation.rawValue)").text
        return mainValue(step).map { UserMessage(key: "history.summary", args: [stepTitle, $0]).text } ?? stepTitle
    }

    private static func mainValue(_ step: TaskStep) -> String? {
        let id: [String] = switch step.kind {
        case .call, .sms: ["recipientName"]
        case .place: ["name", "query"]
        default: ["title"]
        }
        return id.lazy.compactMap { step.field($0)?.value }.first { !$0.isEmpty }
    }

    /// "Hôm nay {HH:mm}" / "Hôm qua {HH:mm}"; older → `common.dateTimeFormat`.
    // TODO(spec): S14 gives no format for dates older than yesterday; `common.dateTimeFormat` used.
    private func relativeTime(_ date: Date) -> String {
        let hhmm = Self.format(date, "HH:mm", calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now()) { return UserMessage(key: "history.time.today", args: [hhmm]).text }
        if let y = calendar.date(byAdding: .day, value: -1, to: now()), calendar.isDate(date, inSameDayAs: y) {
            return UserMessage(key: "history.time.yesterday", args: [hhmm]).text
        }
        return FieldFormatter.dateTime(date, timeZone: calendar.timeZone)
    }

    private static func format(_ date: Date, _ pattern: String, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

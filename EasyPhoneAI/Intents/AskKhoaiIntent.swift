import AppIntents
import SwiftUI

/// D-325 (owner 2026-11-20): "Hỏi Khoai" without opening the app. Back Tap / Action Button / Shortcuts run it; iOS
/// shows its own panel over the current screen: Khoai asks "Bạn cần Khoai làm gì?", the user speaks (keyboard mic)
/// or types, the panel shows the draft and the system "Xác nhận" button. Nothing happens before that tap (D-100).
/// Done in the panel: reminders and events (EventKit, verified, D-124), a day of the calendar (read only).
/// Confirmed in the panel, finished in the app: call / directions (the app must be in front to open Phone / Maps).
/// Everything else (AI requests, SMS, a choice between contacts, mail…) continues in the app with the same words.
struct AskKhoaiIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "intent.ask.title"
    static let description = IntentDescription("intent.ask.desc")
    static let openAppWhenRun = false

    @Parameter(title: "intent.ask.request", requestValueDialog: IntentDialog("intent.ask.prompt"))
    var request: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let env = KhoaiPanel.env, let state = KhoaiPanel.appState else {
            throw needsToContinueInForegroundError()
        }
        let text = SpeechCleanup.fix(request).trimmingCharacters(in: .whitespacesAndNewlines)
        let zone = TimeZone.current
        let panel = KhoaiPanel(env: env, state: state, text: text, zone: zone)
        KhoaiPanel.logger.info("ask khoai")                                // D-059: no content
        let reply = try await answer(panel, text: text, zone: zone)
        return .result(dialog: IntentDialog(stringLiteral: reply.dialog), view: reply.view)
    }

    @MainActor
    private func answer(_ panel: KhoaiPanel, text: String, zone: TimeZone) async throws -> KhoaiPanel.Reply {
        switch LocalIntent.match(text, now: .now, timeZone: zone) {
        case .schedule(let s)?:
            let parsed = s.kind == .reminder
                ? ConversationViewModel.localDraft("reminder", "create", [("title", s.title), ("dueDate", s.date)],
                                                   confidence: ["dueDate": s.dateConfidence])
                : ConversationViewModel.localDraft("calendarEvent", "create",
                                                   [("title", s.title), ("startDate", s.date)]
                                                       + (s.location.map { [("location", $0)] } ?? []),
                                                   confidence: ["startDate": s.dateConfidence])
            return try await panel.run(parsed, inPanel: true, intent: self)
        case .call(let name)?:
            return try await panel.run(ConversationViewModel.localDraft("call", "open",
                                                                        [("recipientName", name), ("callType", "phone")]),
                                       inPanel: false, intent: self)
        case .directions(let label)?:
            return try await panel.run(ConversationViewModel.localDraft("place", "open", [("query", label)]),
                                       inPanel: false, intent: self)
        case .calendarDay(let day)?:
            return try await panel.showDay(day, intent: self)
        case .reminders?:
            throw panel.continueInApp(.reminders, intent: self)
        case .checkMail(let codesOnly)?:
            throw panel.continueInApp(.mail(codesOnly: codesOnly), intent: self)
        case nil:
            throw panel.continueWithText(intent: self)
        }
    }
}

/// The work behind the panel. `env` / `appState` are set by `EasyPhoneApp.init` (same process).
@MainActor struct KhoaiPanel {
    static var env: AppEnvironment?
    static var appState: AppState?
    static let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "khoai")

    let env: AppEnvironment
    let state: AppState
    let text: String
    let zone: TimeZone

    /// What the panel says and shows at the end.
    struct Reply { let dialog: String; let view: KhoaiSnippet }

    /// A local draft → S04 rules on device (resolution, validation) → the system confirmation → execute.
    func run(_ parsed: ParsedDraft, inPanel: Bool, intent: AskKhoaiIntent) async throws -> Reply {
        let draft = TaskDraft(inputMode: .voice, originalInput: text, timeZoneId: zone.identifier)
        env.drafts.save(draft)
        let defaults = DraftBuilder.Defaults(mapsApp: env.localData.settings().preferredMapsApp)
        guard env.engine.applyParsed(parsed, to: draft, defaults: defaults) else {
            throw continueWithText(intent: intent)
        }
        await env.engine.resolveDevice(in: draft)
        guard let step = draft.steps.first else { throw continueWithText(intent: intent) }
        // A choice to make (several "Minh"), a missing field or a permission never asked → S04 in the app.
        let permission: Capability? = switch step.kind {
        case .reminder: .reminders
        case .calendarEvent: .calendar
        default: nil
        }
        let permitted = permission.map { env.permissions.status($0).isUsable } ?? true
        guard env.engine.confirmBlocker(stepId: step.id, in: draft) == nil, permitted else {
            throw continueInApp(.review(draft.id), intent: intent)
        }
        let summary = KhoaiSnippet.summary(of: step, timeZoneId: draft.timeZoneId)
        do {
            try await intent.requestConfirmation(
                result: .result(dialog: IntentDialog(stringLiteral: summary.spoken), view: KhoaiSnippet(.draft(summary))),
                confirmationActionName: .add, showPrompt: false)
        } catch {
            env.engine.cancel(stepId: step.id, in: draft)             // "Hủy" in the panel: nothing done
            throw error
        }
        guard inPanel else {
            // Call / directions: Phone / Maps open only from an app in front (D-102 handedOff there).
            let engine = env.engine, appState = state
            throw intent.needsToContinueInForegroundError(IntentDialog("intent.ask.opening")) {
                _ = await engine.confirm(stepId: step.id, in: draft)
                appState.pendingRoute = .review(draft.id)
            }
        }
        let result = await env.engine.confirm(stepId: step.id, in: draft)
        let done: Bool = if case .finished(.succeeded) = result { true } else { false }
        let message = UserMessage(key: done ? "intent.ask.done" : "intent.ask.failed").text
        return Reply(dialog: message, view: KhoaiSnippet(done ? .done(summary) : .failed(message)))
    }

    /// "Xem lịch ngày mai": the day's events in the panel (read only). No permission yet → S11 in the app.
    func showDay(_ day: String, intent: AskKhoaiIntent) async throws -> Reply {
        guard env.permissions.status(.calendar).isUsable, let range = Self.interval(day, zone),
              let events = try? await env.calendar.events(in: range) else {
            throw continueInApp(.calendarDay(day), intent: intent)
        }
        let rows = events.sorted { $0.start < $1.start }.prefix(6).map { e in
            e.isAllDay ? e.title : "\(e.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))) \(e.title)"
        }
        let title = UserMessage(key: events.isEmpty ? "intent.ask.day.empty" : "intent.ask.day",
                                args: [Self.dayLabel(range.start, zone)]).text
        return Reply(dialog: title, view: KhoaiSnippet(.list(title: title, rows: Array(rows))))
    }

    func continueInApp(_ route: Route, intent: AskKhoaiIntent) -> Error {
        let appState = state
        return intent.needsToContinueInForegroundError(IntentDialog("intent.ask.opening")) {
            appState.pendingRoute = route
        }
    }

    /// AI requests and the rest: the same words become a typed request in S03 (sent on arrival, D-104 saved first).
    func continueWithText(intent: AskKhoaiIntent) -> Error {
        let draft = TaskDraft(inputMode: .text, originalInput: text, timeZoneId: zone.identifier)
        env.drafts.save(draft)
        return continueInApp(.conversation(draft.id), intent: intent)
    }

    static func interval(_ day: String, _ zone: TimeZone) -> DateInterval? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd"
        guard let start = f.date(from: day) else { return nil }
        return DateInterval(start: start, duration: 86_400)
    }

    static func dayLabel(_ date: Date, _ zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "vi_VN"))
        style.timeZone = zone
        return date.formatted(style)
    }
}

import OSLog

/// The panel content (a static SwiftUI snapshot drawn by iOS; no animation). Khoai + one card.
struct KhoaiSnippet: View {
    struct Summary: Sendable, Hashable {
        var symbol: String
        var lines: [String]
        var spoken: String
    }

    enum Content { case draft(Summary), done(Summary), failed(String), list(title: String, rows: [String]) }

    let content: Content

    init(_ content: Content) { self.content = content }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(pose)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                switch content {
                case .draft(let s), .done(let s):
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(s.lines, id: \.self) { Text(verbatim: $0) }
                        }
                    } icon: { Image(systemName: isDone ? "checkmark.circle.fill" : s.symbol) }
                    .font(.headline)
                case .failed(let message):
                    Label { Text(verbatim: message) } icon: { Image(systemName: "exclamationmark.circle") }
                case .list(let title, let rows):
                    Text(verbatim: title).font(.headline)
                    ForEach(rows, id: \.self) { Text(verbatim: $0).font(.body) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    private var isDone: Bool { if case .done = content { true } else { false } }

    private var pose: String {
        switch content {
        case .done: "mascot.jumping.00"
        case .failed: "mascot.failed.00"
        default: "mascot.waving.00"
        }
    }

    /// "Nhắc: Uống thuốc" + "20:00 Thứ Năm 20/11" (field formatting as S04).
    @MainActor static func summary(of step: TaskStep, timeZoneId: String) -> Summary {
        func value(_ id: String) -> String? {
            step.field(id).flatMap { FieldFormatter.display($0, timeZoneId: timeZoneId) }
        }
        let (symbol, key, main, detail): (String, String, String?, String?) = switch step.kind {
        case .reminder: ("bell.fill", "intent.ask.kind.reminder", value("title"), value("dueDate"))
        case .calendarEvent: ("calendar", "intent.ask.kind.event", value("title"), value("startDate"))
        case .call: ("phone.fill", "intent.ask.kind.call", value("recipientName"), nil)
        case .place: ("map.fill", "intent.ask.kind.place", value("name") ?? value("query"), nil)
        default: ("sparkles", "intent.ask.kind.other", nil, nil)
        }
        let first = UserMessage(key: key, args: [main ?? ""]).text
        let lines = [first] + (detail.map { [$0] } ?? [])
        return Summary(symbol: symbol, lines: lines, spoken: lines.joined(separator: ", "))
    }
}

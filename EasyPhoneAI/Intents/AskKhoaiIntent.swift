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
            return try await panel.finish(parsed, in: panel.newDraft(), intent: self)
        case .call(let name)?:
            return try await panel.finish(ConversationViewModel.localDraft("call", "open",
                                                                           [("recipientName", name), ("callType", "phone")]),
                                          in: panel.newDraft(), intent: self)
        case .directions(let label)?:
            return try await panel.finish(ConversationViewModel.localDraft("place", "open", [("query", label)]),
                                          in: panel.newDraft(), intent: self)
        case .calendarDay(let day)?:
            return try await panel.showDay(day, intent: self)
        case .reminders?:
            throw panel.continueInApp(.reminders, intent: self)
        case .checkMail(let codesOnly)?:
            throw panel.continueInApp(.mail(codesOnly: codesOnly), intent: self)
        case nil:
            return try await panel.askAI(intent: self)                       // step 2 (D-325)
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

    /// The panel's draft: typed, so if it continues in the app S03 sends / resumes it like a typed request (D-104).
    func newDraft() -> TaskDraft {
        let draft = TaskDraft(inputMode: .text, originalInput: text, timeZoneId: zone.identifier)
        env.drafts.save(draft)
        return draft
    }

    /// Step 2: `/v1/parse` from the panel (1 unit, same pipeline and idempotency as S03). Errors (offline, quota,
    /// sign-in) continue in the app, where S03 shows the proper screen for them.
    func askAI(intent: AskKhoaiIntent) async throws -> Reply {
        let draft = newDraft()
        var seen = Set<String>()
        let labels = env.localData.savedPlaces().map(\.label).filter { seen.insert($0).inserted }   // labels only
        let request = ParseRequest(text: text, inputMode: .voice, now: ParseRequest.nowString(.now, in: zone),
                                   timezone: zone.identifier, locale: draft.locale, savedPlaceLabels: labels,
                                   context: .none)
        let parsed: ParsedDraft
        do {
            parsed = try await env.api.parse(request, idempotencyKey: IdempotencyKey())
        } catch {
            Self.logger.info("ask khoai parse failed: \((error as? AppError)?.code ?? "unknown", privacy: .public)")
            throw continueInApp(.conversation(draft.id), intent: intent)
        }
        if let u = parsed.unsupported {
            switch u.reason {
            case "viewCalendar":
                return try await showDay(u.date ?? ConversationViewModel.dayString(.now, timeZoneId: zone.identifier),
                                         intent: intent)
            case "checkMail":
                throw continueInApp(.mail(codesOnly: LocalIntent.wantsCode(text)), intent: intent)
            default:
                let message = UserMessage(key: "intent.ask.unsupported").text           // spec §11 "Chưa hỗ trợ"
                return Reply(dialog: message, view: KhoaiSnippet(.failed(message)))
            }
        }
        return try await finish(parsed, in: draft, intent: intent)
    }

    /// Kinds the panel may finish itself (create only: edit / delete always go to S04, D-108).
    static func panelKind(_ step: TaskStep) -> Bool {
        step.operation == .create && (step.kind == .reminder || step.kind == .calendarEvent)
    }

    /// Kinds confirmed in the panel but run by the app in front (Phone / Maps hand-off, D-102).
    static func handoffKind(_ step: TaskStep) -> Bool {
        step.operation == .open && (step.kind == .call || step.kind == .place)
    }

    /// A parsed draft (local or AI) → device resolution and S04 rules → one system confirmation for all steps →
    /// run. Anything the panel cannot show or decide continues in S03 / S04 with this same draft (nothing re-parsed).
    func finish(_ parsed: ParsedDraft, in draft: TaskDraft, intent: AskKhoaiIntent) async throws -> Reply {
        let defaults = DraftBuilder.Defaults(mapsApp: env.localData.settings().preferredMapsApp)
        guard env.engine.applyParsed(parsed, to: draft, defaults: defaults) else {
            let message = UserMessage(key: "intent.ask.unsupported").text
            return Reply(dialog: message, view: KhoaiSnippet(.failed(message)))
        }
        await env.engine.resolveDevice(in: draft)
        let steps = draft.steps.sorted { $0.order < $1.order }
        let allowed = steps.allSatisfy { Self.panelKind($0) || Self.handoffKind($0) }
        let permitted = steps.allSatisfy { step in
            switch step.kind {
            case .reminder: env.permissions.status(.reminders).isUsable
            case .calendarEvent: env.permissions.status(.calendar).isUsable
            default: true
            }
        }
        // Only the first step can be confirmable before the others are done (linked steps, DATA_MODEL §3.3).
        let ready = steps.first.map { env.engine.confirmBlocker(stepId: $0.id, in: draft) == nil } ?? false
        let complete = steps.allSatisfy { Validator.validate($0, now: .now).isEmpty }
        guard allowed, permitted, ready, complete, env.engine.nextFollowUp(in: draft) == nil else {
            throw continueInApp(.conversation(draft.id), intent: intent)        // S03 resumes: follow-up / S04
        }
        let summaries = steps.map { KhoaiSnippet.summary(of: $0, timeZoneId: draft.timeZoneId) }
        let merged = KhoaiSnippet.Summary(symbol: summaries.count == 1 ? summaries[0].symbol : "list.bullet",
                                          lines: summaries.flatMap(\.lines),
                                          spoken: summaries.map(\.spoken).joined(separator: ". "))
        do {
            try await intent.requestConfirmation(
                result: .result(dialog: IntentDialog(stringLiteral: merged.spoken), view: KhoaiSnippet(.draft(merged))),
                confirmationActionName: .add, showPrompt: false)
        } catch {
            for step in steps { env.engine.cancel(stepId: step.id, in: draft) }   // "Hủy": nothing done
            throw error
        }
        let engine = env.engine
        if steps.contains(where: Self.handoffKind) {
            let appState = state
            throw intent.needsToContinueInForegroundError(IntentDialog("intent.ask.opening")) {
                for step in steps { _ = await engine.confirm(stepId: step.id, in: draft) }
                appState.pendingRoute = .review(draft.id)
            }
        }
        var allDone = true
        for step in steps {
            let result = await engine.confirm(stepId: step.id, in: draft)
            if case .finished(.succeeded) = result { continue }
            allDone = false
            break
        }
        let message = UserMessage(key: allDone ? "intent.ask.done" : "intent.ask.failed").text
        return Reply(dialog: message, view: KhoaiSnippet(allDone ? .done(merged) : .failed(message)))
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

/// D-325: the ready-made "Khoai nghe" shortcut (Dictate Text in Vietnamese → "Hỏi Khoai") shared from the owner's
/// iPhone as an iCloud link; S15 "Gọi Khoai nhanh" opens it so users only tap "Thêm phím tắt". nil → manual steps.
enum KhoaiShortcut {
    static let iCloudURL: URL? = URL(string: "https://www.icloud.com/shortcuts/81b9237515f9486f879eec543839fc5b")   // owner 2026-11-20
}

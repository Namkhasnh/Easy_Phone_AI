import AppIntents
import SwiftUI

/// D-325 (owner 2026-11-20): "Hỏi Khoai" without opening the app. Back Tap / Action Button / Shortcuts run it; iOS
/// shows its own panel over the current screen: Khoai asks "Bạn cần Khoai làm gì?", the user speaks (keyboard mic)
/// or types, the panel shows the draft and the system "Xác nhận" button. Nothing happens before that tap (D-100).
/// Done in the panel: reminders and events (EventKit, verified, D-124), a day of the calendar (read only).
/// Confirmed in the panel, finished in the app: call / directions (the app must be in front to open Phone / Maps).
/// Everything else (AI requests, SMS, a choice between contacts, mail…) continues in the app with the same words.
/// 4H.5: "làm sao …" is answered in the panel one step at a time; "tiếp" said to the panel later gives the next step
/// (`GuideSessions`), so the user stays in Zalo / Cài đặt. `LiveActivityIntent`: may start "Bước 1/5" from the background.
struct AskKhoaiIntent: AppIntent, ForegroundContinuableIntent, LiveActivityIntent {
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
        return .result(dialog: reply.dialog, view: reply.view)
    }

    @MainActor
    private func answer(_ panel: KhoaiPanel, text: String, zone: TimeZone) async throws -> KhoaiPanel.Reply {
        if let outcome = panel.env.guideSessions.handle(text) { return KhoaiPanel.guideReply(outcome) }   // 4H.5
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
        case .lunar(let question)?:                                         // 4L.2: answered on the phone
            let text = question.answer(now: .now)
            return KhoaiPanel.Reply(full: text, shown: UserMessage(key: "intent.ask.lunar").text,
                                    view: KhoaiSnippet(.list([KhoaiSnippet.Row(time: nil, title: text)])))
        case .calendarDay(let day)?:
            return try await panel.showDay(day, intent: self)
        case .reminders?:
            throw panel.continueInApp(.reminders, intent: self)
        case .checkMail(let codesOnly)?:
            throw panel.continueInApp(.mail(codesOnly: codesOnly), intent: self)
        case .guide(let question)?:                                         // 4H.5: step 1 in the panel
            return try await panel.guide(question, intent: self)
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

    /// What the panel says and shows at the end. `shown` = iOS's header line over the snippet (short, never repeated
    /// in the view); `full` = what Siri reads aloud (with the item details, for voice-only use).
    struct Reply {
        let full: String
        let shown: String
        let view: KhoaiSnippet

        init(full: String, shown: String, view: KhoaiSnippet) { self.full = full; self.shown = shown; self.view = view }
        init(_ message: String, view: KhoaiSnippet) { self.init(full: message, shown: message, view: view) }

        var dialog: IntentDialog { Self.dialog(full: full, shown: shown) }

        static func dialog(full: String, shown: String) -> IntentDialog {
            full == shown ? IntentDialog(stringLiteral: full)
                : IntentDialog(full: LocalizedStringResource(stringLiteral: full),
                               supporting: LocalizedStringResource(stringLiteral: shown))
        }
    }

    static func failed(_ key: String, hint: String) -> Reply {
        Reply(UserMessage(key: key).text, view: KhoaiSnippet(.failed(hint: UserMessage(key: hint).text)))
    }

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
            draft.markAnswered(parsed.requestId)                       // not an unsent request in S02 (1G.10)
            env.drafts.save(draft)
            switch u.reason {
            case "viewCalendar":
                return try await showDay(u.date ?? ConversationViewModel.dayString(.now, timeZoneId: zone.identifier),
                                         intent: intent)
            case "checkMail":
                throw continueInApp(.mail(codesOnly: LocalIntent.wantsCode(text)), intent: intent)
            default:
                return Self.failed("intent.ask.unsupported", hint: "intent.ask.unsupported.hint")   // spec §11
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
        let defaults = DraftBuilder.Defaults(mapsApp: env.localData.settings().preferredMapsApp, timeZoneId: draft.timeZoneId)
        guard env.engine.applyParsed(parsed, to: draft, defaults: defaults) else {
            draft.markAnswered(parsed.requestId)
            env.drafts.save(draft)
            return Self.failed("intent.ask.unsupported", hint: "intent.ask.unsupported.hint")
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
        let spoken = summaries.map(\.spoken).joined(separator: ". ")
        // D-326 (owner 2026-11-20): "Làm luôn, không cần xác nhận" (D-299) in the panel = no confirmation for safe
        // creates; the done card has "Hoàn tác" instead of the in-app 3 s countdown.
        let auto = env.localData.settings().autoConfirm && steps.allSatisfy(Self.panelKind)
        if auto { return await runAll(steps, draft: draft, summaries: summaries, undo: true) }
        do {
            try await intent.requestConfirmation(
                result: .result(dialog: Reply.dialog(full: spoken, shown: UserMessage(key: "intent.ask.confirm").text),
                                view: KhoaiSnippet(.draft(summaries))),
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
        return await runAll(steps, draft: draft, summaries: summaries, undo: false)
    }

    private func runAll(_ steps: [TaskStep], draft: TaskDraft, summaries: [KhoaiSnippet.Summary], undo: Bool) async -> Reply {
        var allDone = true
        for step in steps {
            let result = await env.engine.confirm(stepId: step.id, in: draft)
            if case .finished(.succeeded) = result { continue }
            allDone = false
            break
        }
        guard allDone else { return Self.failed("intent.ask.failed", hint: "intent.ask.failed.hint") }
        let message = UserMessage(key: "intent.ask.done").text
        let spoken = summaries.map(\.spoken).joined(separator: ". ")
        return Reply(full: "\(message) \(spoken)", shown: message,
                     view: KhoaiSnippet(.done(summaries, undoDraftId: undo ? draft.id.uuidString : nil)))
    }

    /// D-326 "Hoàn tác": each item the draft created gets a delete step, confirmed by this tap (D-108: a tap, never
    /// voice). Through `TaskEngine` like S11 / S12 deletes, so history shows both.
    func undo(draftId: UUID) async -> Reply {
        guard let draft = env.drafts.draft(draftId) else {
            return Self.failed("intent.ask.failed", hint: "intent.ask.failed.hint")
        }
        let removed = draft.steps.sorted { $0.order < $1.order }.filter { $0.state == .succeeded }
            .map { KhoaiSnippet.summary(of: $0, timeZoneId: draft.timeZoneId) }
        var ok = true
        for step in draft.steps where step.state == .succeeded {
            var undoDraft: TaskDraft?
            if let id = CalendarExecutor.eventId(step.resultEvidence), let event = try? await env.calendar.find(identifier: id) {
                undoDraft = env.engine.startDraft(from: event, operation: .delete, timeZoneId: draft.timeZoneId)
            } else if let id = RemindersExecutor.reminderId(step.resultEvidence),
                      let reminder = try? await env.reminders.find(identifier: id) {
                undoDraft = env.engine.startDraft(from: reminder, operation: .delete, timeZoneId: draft.timeZoneId)
            }
            guard let undoDraft, let undoStep = undoDraft.steps.first,
                  case .finished(.succeeded) = await env.engine.confirm(stepId: undoStep.id, in: undoDraft) else {
                ok = false
                continue
            }
        }
        guard ok else { return Self.failed("intent.ask.failed", hint: "intent.ask.failed.hint") }
        return Reply(full: UserMessage(key: "intent.ask.undone").text, shown: UserMessage(key: "intent.ask.undone.title").text,
                     view: KhoaiSnippet(.undone(removed)))
    }

    /// "Xem lịch ngày mai": the day's events in the panel (read only). No permission yet → S11 in the app.
    func showDay(_ day: String, intent: AskKhoaiIntent) async throws -> Reply {
        guard env.permissions.status(.calendar).isUsable, let range = Self.interval(day, zone),
              let events = try? await env.calendar.events(in: range) else {
            throw continueInApp(.calendarDay(day), intent: intent)
        }
        let rows = events.sorted { $0.start < $1.start }.prefix(6).map { e in
            KhoaiSnippet.Row(time: e.isAllDay ? nil
                                : e.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)),
                             title: e.title)
        }
        let title = UserMessage(key: events.isEmpty ? "intent.ask.day.empty" : "intent.ask.day",
                                args: [Self.dayLabel(range.start, zone)]).text
        let spoken = rows.map { [$0.time, $0.title].compactMap { $0 }.joined(separator: " ") }.joined(separator: ". ")
        return Reply(full: spoken.isEmpty ? title : "\(title). \(spoken)", shown: title, view: KhoaiSnippet(.list(Array(rows))))
    }

    // MARK: - Guide (4H.5, D-337 – D-340)

    /// "làm sao gửi ảnh Zalo" → step 1 in the panel; later "tiếp" → step 2 (`GuideSessions.handle`). Money guides
    /// continue in S23 (all warnings + "Gọi cho con", D-339) with the same loaded guide, so no second unit.
    /// Offline / quota / sign-in errors → S23, which shows the proper screen.
    func guide(_ question: String, intent: AskKhoaiIntent) async throws -> Reply {
        let loaded: Guide?
        do {
            loaded = try await GuideLoader.load(question, library: .bundled, api: env.api, key: IdempotencyKey())
        } catch {
            Self.logger.info("ask khoai guide failed: \((error as? AppError)?.code ?? "unknown", privacy: .public)")
            throw continueInApp(.guide(question: question, spoken: false), intent: intent)
        }
        guard let loaded else { return Self.failed("common.unsupported", hint: "guide.unsupported.body") }
        let session = env.guideSessions.start(loaded, question: question)
        // TODO(spec): D-339 lists the money warnings and "Gọi cho con" but not the panel; money → S23 is Claude's choice.
        if loaded.isMoneyRelated || GuideSafety.isMoneyRelated(question) {
            throw continueInApp(.guide(question: question, spoken: false), intent: intent)
        }
        return Self.guideReply(.step(session), first: true)
    }

    /// One step: header "Bước 2/5", the step in big text, how to get the next one. Siri reads the whole step.
    static func guideReply(_ outcome: GuideSessions.Outcome, first: Bool = false) -> Reply {
        func line(_ text: String) -> KhoaiSnippet { KhoaiSnippet(.list([KhoaiSnippet.Row(time: nil, title: text)])) }
        switch outcome {
        case .step(let s):
            let footer = UserMessage(key: s.isLast ? "guide.panel.last" : "guide.panel.next").text
            let warning = s.guide.isMoneyRelated ? UserMessage(key: "guide.warning.otp").text : nil   // D-339
            let full = ([first && !s.guide.title.isEmpty ? s.guide.title : nil, warning, s.spoken, footer])
                .compactMap { $0 }.joined(separator: ". ")
            let card = KhoaiSnippet.GuideCard(title: s.guide.title, label: s.label, text: s.step.text, hint: s.step.hint,
                                              warning: warning, footer: footer, canGoBack: s.index > 0,
                                              canGoOn: !s.isLast)
            return Reply(full: full, shown: s.label, view: KhoaiSnippet(.guide(card)))
        case .finished:
            let text = UserMessage(key: "guide.panel.finished").text
            return Reply(text, view: line(UserMessage(key: "guide.panel.finished.body").text))
        case .stopped:
            let text = UserMessage(key: "guide.panel.stopped").text
            return Reply(text, view: line(UserMessage(key: "guide.panel.start.hint").text))
        case .noGuide:
            return failed("guide.panel.none", hint: "guide.panel.start.hint")
        }
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

/// The panel content under iOS's own header (the dialog's `supporting` text) and above the system buttons
/// (owner 2026-11-22: real panel = header + divider + this view + "Done" / "Thêm"). A static snapshot (no animation):
/// a still Khoai cut from the video clips + one card per item. The header already says the short message, so the
/// view never repeats it.
struct KhoaiSnippet: View {
    enum Kind: Sendable, Hashable { case reminder, event, call, place, other }

    struct Summary: Sendable, Hashable {
        var kind: Kind
        var symbol: String
        var title: String
        var detail: String?
        /// "Nhắc: Uống thuốc" + detail: what Siri reads aloud.
        var lines: [String]
        var spoken: String { lines.joined(separator: ", ") }
    }

    struct Row: Sendable, Hashable { var time: String?; var title: String }

    /// 4H.5: one guide step in the panel.
    struct GuideCard: Sendable, Hashable {
        var title: String
        var label: String
        var text: String
        var hint: String?
        /// Money guide (D-339): "Không đọc mã OTP cho ai".
        var warning: String?
        var footer: String
        var canGoBack: Bool
        var canGoOn: Bool
    }

    enum Content {
        case draft([Summary]), done([Summary], undoDraftId: String? = nil), undone([Summary])
        case failed(hint: String)
        case list([Row])
        case guide(GuideCard)
    }

    let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ content: Content) { self.content = content }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack(alignment: .center, spacing: Tokens.Space.m) {
                if typeSize < .accessibility1 {
                    Image(pose)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Tokens.Space.s) { cards }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if case .done(_, let undoId?) = content { undoButton(undoId) }
            if case .guide(let card) = content { guideButtons(card) }
        }
        .padding(.horizontal, Tokens.Space.l)
        .padding(.vertical, Tokens.Space.m)
    }

    @ViewBuilder private var cards: some View {
        switch content {
        case .draft(let items): ForEach(items, id: \.self) { card($0, status: nil) }
        case .done(let items, _): ForEach(items, id: \.self) { card($0, status: .done) }
        case .undone(let items): ForEach(items, id: \.self) { card($0, status: .removed) }
        case .failed(let hint):
            Text(verbatim: hint)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        case .guide(let card):
            guideCard(card)
        case .list(let rows):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Divider() }
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                        Text(verbatim: row.time ?? "•")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.red)
                            .frame(minWidth: 48, alignment: .leading)
                        Text(verbatim: row.title).font(.body.weight(.medium))
                    }
                    .padding(.vertical, Tokens.Space.s)
                }
            }
            .padding(.horizontal, Tokens.Space.m)
            .background(Tokens.Colors.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }
    }

    private enum Status { case done, removed }

    private func card(_ s: Summary, status: Status?) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            Image(systemName: s.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Self.tint(s.kind), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.label(s.kind))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: s.title)
                    .font(.title3.weight(.bold))
                    .strikethrough(status == .removed)
                    .foregroundStyle(status == .removed ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = s.detail {
                    Label { Text(verbatim: detail) } icon: { Image(systemName: "clock") }
                        .font(.callout)
                        .foregroundStyle(status == .removed ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let status {
                    Label { Text(status == .done ? Self.doneLabel(s.kind) : "intent.ask.status.removed") }
                        icon: { Image(systemName: status == .done ? "checkmark.circle.fill" : "trash") }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(status == .done ? Tokens.Colors.success : .secondary)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.m)
        .background(Tokens.Colors.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .accessibilityElement(children: .combine)
    }

    /// D-326: interactive snippet buttons exist from iOS 26; earlier the item stays (S11 / S12 can delete it).
    @ViewBuilder private func undoButton(_ draftId: String) -> some View {
        if #available(iOS 26.0, *) {
            Button(intent: UndoKhoaiIntent(draftId: draftId)) {
                Label { Text("intent.ask.undo") } icon: { Image(systemName: "arrow.uturn.backward") }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Tokens.Colors.primary)
        }
    }

    private func guideCard(_ card: GuideCard) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            if !card.title.isEmpty {
                Text(verbatim: card.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let warning = card.warning {
                Label { Text(verbatim: warning) } icon: { Image(systemName: "exclamationmark.shield.fill") }
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: card.text)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            if let hint = card.hint {
                Label { Text(verbatim: hint) } icon: { Image(systemName: "lightbulb") }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: card.footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colors.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .accessibilityElement(children: .combine)
    }

    /// 4H.5: "Bước trước" / "Bước tiếp" in the panel (interactive snippets, iOS 26); earlier: say "tiếp" to Khoai.
    @ViewBuilder private func guideButtons(_ card: GuideCard) -> some View {
        if #available(iOS 26.0, *) {
            HStack(spacing: Tokens.Space.m) {
                if card.canGoBack {
                    Button(intent: GuideStepIntent(move: .previous)) {
                        Text("guide.previous").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                if card.canGoOn {
                    Button(intent: GuideStepIntent(move: .next)) {
                        Text("guide.next").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .tint(Tokens.Colors.primary)
        }
    }

    private var pose: String {
        switch content {
        case .done: "mascot.panel.happy"
        case .failed: "mascot.panel.sorry"
        case .draft: "mascot.panel.ask"
        case .undone, .list, .guide: "mascot.panel.calm"
        }
    }

    static func tint(_ kind: Kind) -> Color {
        switch kind {
        case .reminder: .orange
        case .event: .red
        case .call: .green
        case .place: .blue
        case .other: Tokens.Colors.primary
        }
    }

    static func label(_ kind: Kind) -> LocalizedStringKey {
        switch kind {
        case .reminder: "intent.ask.label.reminder"
        case .event: "intent.ask.label.event"
        case .call: "intent.ask.label.call"
        case .place: "intent.ask.label.place"
        case .other: "intent.ask.label.other"
        }
    }

    static func doneLabel(_ kind: Kind) -> LocalizedStringKey {
        kind == .event ? "intent.ask.status.event" : "intent.ask.status.reminder"
    }

    /// Title "Uống thuốc", detail "Thứ Năm, 20/11 lúc 20:00" (field formatting as S04); spoken "Nhắc: Uống thuốc, …".
    @MainActor static func summary(of step: TaskStep, timeZoneId: String) -> Summary {
        func value(_ id: String) -> String? {
            step.field(id).flatMap { FieldFormatter.display($0, timeZoneId: timeZoneId) }
        }
        let (kind, symbol, key, main, detail): (Kind, String, String, String?, String?) = switch step.kind {
        case .reminder: (.reminder, "bell.fill", "intent.ask.kind.reminder", value("title"), value("dueDate"))
        case .calendarEvent: (.event, "calendar", "intent.ask.kind.event", value("title"), value("startDate"))
        case .call: (.call, "phone.fill", "intent.ask.kind.call", value("recipientName"), nil)
        case .place: (.place, "map.fill", "intent.ask.kind.place", value("name") ?? value("query"), nil)
        default: (.other, "sparkles", "intent.ask.kind.other", nil, nil)
        }
        let first = UserMessage(key: key, args: [main ?? ""]).text
        return Summary(kind: kind, symbol: symbol, title: main ?? first, detail: detail,
                       lines: [first] + (detail.map { [$0] } ?? []))
    }
}

/// D-325: the ready-made "Khoai nghe" shortcut (Dictate Text in Vietnamese → "Hỏi Khoai") shared from the owner's
/// iPhone as an iCloud link; S15 "Gọi Khoai nhanh" opens it so users only tap "Thêm phím tắt". nil → manual steps.
enum KhoaiShortcut {
    static let iCloudURL: URL? = URL(string: "https://www.icloud.com/shortcuts/81b9237515f9486f879eec543839fc5b")   // owner 2026-11-20
}

/// D-326: "Hoàn tác" on the done card of an automatic panel run. Not shown in Shortcuts (only the card uses it).
struct UndoKhoaiIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.ask.undo"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "intent.ask.undo") var draftId: String

    init() {}
    init(draftId: String) { self.draftId = draftId }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let env = KhoaiPanel.env, let state = KhoaiPanel.appState, let id = UUID(uuidString: draftId) else {
            let reply = KhoaiPanel.failed("intent.ask.failed", hint: "intent.ask.failed.hint")
            return .result(dialog: reply.dialog, view: reply.view)
        }
        let reply = await KhoaiPanel(env: env, state: state, text: "", zone: .current).undo(draftId: id)
        return .result(dialog: reply.dialog, view: reply.view)
    }
}

/// 4H.5: "Bước tiếp" / "Bước trước" on the panel's guide card. Not shown in Shortcuts (only the card uses it).
struct GuideStepIntent: AppIntent, LiveActivityIntent {
    enum Move: String, AppEnum {
        case next, previous
        static let typeDisplayRepresentation: TypeDisplayRepresentation = "intent.guideStep.title"
        static let caseDisplayRepresentations: [Move: DisplayRepresentation] = [
            .next: "guide.next", .previous: "guide.previous",
        ]
    }

    static let title: LocalizedStringResource = "intent.guideStep.title"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "intent.guideStep.title") var move: Move

    init() {}
    init(move: Move) { self.move = move }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let outcome = KhoaiPanel.env?.guideSessions.handle(move == .next ? "tiếp" : "quay lại") ?? .noGuide
        let reply = KhoaiPanel.guideReply(outcome)
        return .result(dialog: reply.dialog, view: reply.view)
    }
}

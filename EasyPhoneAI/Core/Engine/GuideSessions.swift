import Foundation

/// 4H.3 / 4H.5 (D-338, D-340): where a guide comes from. Curated set on the phone first (no unit), else
/// `POST /v1/guide` with the question masked on the phone. nil = "Chưa hỗ trợ". Shared by S23 and the Hỏi Khoai panel.
enum GuideLoader {
    static func load(_ question: String, library: GuideLibrary, api: any APIClientProtocol,
                     key: IdempotencyKey) async throws -> Guide? {
        if let entry = library.match(question) { return entry.guide }
        let request = GuideRequest(question: GuideSafety.masked(question), locale: "vi-VN")
        return try await api.guide(request, idempotencyKey: key).guide
    }
}

extension Guide {
    /// "Bước 2/5".
    static func stepLabel(_ index: Int, of total: Int) -> String {
        UserMessage(key: "guide.step", args: [String(index + 1), String(total)]).text
    }

    /// What one step reads aloud: "Bước 2/5. <text>. <hint>".
    func spoken(_ index: Int) -> String {
        guard steps.indices.contains(index) else { return "" }
        let step = steps[index]
        return [Self.stepLabel(index, of: steps.count), step.text, step.hint].compactMap { $0 }.joined(separator: ". ")
    }
}

/// The guide being followed (4H.5): the step the user is on, kept on the phone so the Hỏi Khoai panel (Back Tap, D-325)
/// can say the next step while the user is in Zalo / Cài đặt, and S23 picks up where the panel left off.
struct GuideSession: Codable, Sendable, Hashable {
    /// Masked like the request (D-340), only to recognise the same question again in S23.
    var question: String
    var guide: Guide
    var index: Int
    var updatedAt: Date

    var step: GuideResponse.Step { guide.steps[index] }
    var isLast: Bool { index >= guide.steps.count - 1 }
    var label: String { Guide.stepLabel(index, of: guide.steps.count) }
    var spoken: String { guide.spoken(index) }
}

/// 4H.5: the one guide session (UserDefaults, survives the app being closed in the background) + its Live Activity.
/// Nothing in it runs anything: it only remembers which step to show (D-337).
struct GuideSessions: Sendable {
    // TODO(spec): D-337 / D-325 do not say how long a guide stays "open" for "tiếp" in the panel; 30 min is Claude's choice.
    static let lifetime: TimeInterval = 30 * 60
    private static let key = "guide.session.v1"

    /// nil = `UserDefaults.standard`; tests / mocks use their own suite. (A name, not the object: UserDefaults is not
    /// `Sendable`.)
    let suiteName: String?
    let progress: any GuideProgressService

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    /// The open guide, or nil (none, or older than `lifetime` → cleared).
    @MainActor func current(now: Date = .now) -> GuideSession? {
        guard let data = defaults.data(forKey: Self.key),
              let session = try? JSONDecoder().decode(GuideSession.self, from: data),
              session.guide.steps.indices.contains(session.index) else { return nil }
        guard now.timeIntervalSince(session.updatedAt) <= Self.lifetime else {
            end()
            return nil
        }
        return session
    }

    /// The question's session if it is the one open (S23 opened again, or continued from the panel: no second unit).
    @MainActor func current(for question: String, now: Date = .now) -> GuideSession? {
        current(now: now).flatMap { $0.question == GuideSafety.masked(question) ? $0 : nil }
    }

    @discardableResult
    @MainActor func start(_ guide: Guide, question: String, now: Date = .now) -> GuideSession {
        let session = GuideSession(question: GuideSafety.masked(question), guide: guide, index: 0, updatedAt: now)
        save(session)
        return session
    }

    @discardableResult
    @MainActor func move(to index: Int, now: Date = .now) -> GuideSession? {
        guard var session = current(now: now), session.guide.steps.indices.contains(index) else { return nil }
        session.index = index
        session.updatedAt = now
        save(session)
        return session
    }

    @MainActor func end() {
        defaults.removeObject(forKey: Self.key)
        progress.end()
    }

    @MainActor private func save(_ session: GuideSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: Self.key)
        progress.show(GuideProgress(title: session.guide.title, label: session.label, text: session.step.text,
                                    step: session.index + 1, total: session.guide.steps.count))
    }

    // MARK: - Panel words (D-312 words, D-325 panel)

    enum Outcome: Equatable, Sendable {
        case step(GuideSession)
        /// "tiếp" on the last step: the guide is done (session ended).
        case finished
        /// "thôi".
        case stopped
        /// A guide word but no guide is open.
        case noGuide
    }

    /// "tiếp" / "nói lại" / "quay lại" / "thôi" said to the panel. nil = not a guide word → the normal panel flow.
    /// Short only (≤ 4 words with a guide open, ≤ 2 without), so "nhắc tôi tiếp tục uống thuốc" stays a task.
    @MainActor func handle(_ text: String, now: Date = .now) -> Outcome? {
        let words = GuideLibrary.fold(text).split(separator: " ").count
        let command = GuideVoiceCommand.classify(text)
        guard command != .other else { return nil }
        guard let session = current(now: now) else { return words <= 2 ? .noGuide : nil }
        guard words <= 4 else { return nil }
        switch command {
        case .next:
            guard !session.isLast else { end(); return .finished }
            return move(to: session.index + 1, now: now).map(Outcome.step)
        case .previous:
            return move(to: max(session.index - 1, 0), now: now).map(Outcome.step)
        case .repeatStep:
            return move(to: session.index, now: now).map(Outcome.step)
        case .stop:
            end()
            return .stopped
        case .other:
            return nil
        }
    }
}

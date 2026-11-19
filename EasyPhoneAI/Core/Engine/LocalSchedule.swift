import Foundation

/// D-320 (owner 2026-11-19, speed): reminders and events with a clear time, understood on the phone without
/// `/v1/parse` (~0.1 s instead of ~4 s, no unit). Same rules as `parse.v6` DATES AND TIMES, narrowed on purpose:
/// today / "mai" / "ngày kia" / "X phút|tiếng nữa" + one explicit hour. Anything else — weekday, numeric date, recurring,
/// "nhắc trước", "kém", lunar, edit / delete, several actions, a time already passed with no day, a name that could be
/// "Mai" — returns nil and goes to the AI as before. The result is only a draft: S04 + "Xác nhận" as usual (D-100).
enum LocalSchedule {
    struct Result: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case reminder, event }
        var kind: Kind
        var title: String
        /// ISO 8601 with offset (DATA_MODEL §1 `dateTime`).
        var date: String
        /// 0.6 when the day part was guessed ("8 giờ" → 08:00), as parse.v6 does, so S04 highlights it.
        var dateConfidence: Double
        var location: String?
    }

    private struct Token { let original: String; let folded: String }

    static func match(_ text: String, now: Date, timeZone: TimeZone) -> Result? {
        // "8:30" / "8.30" → "8h30" before splitting into words.
        let prepared = text.replacingOccurrences(of: #"(\d{1,2})[:.](\d{2})"#, with: "$1h$2", options: .regularExpression)
        let words = LocalIntent.Words(prepared)
        let tokens = zip(words.original, words.folded).map { Token(original: $0, folded: $1) }
        guard (2...16).contains(tokens.count) else { return nil }
        let f = tokens.map(\.folded)
        guard !f.contains(where: rejected.contains) else { return nil }
        guard !zip(f, f.dropFirst()).contains(where: { $0.0 == "ngay" && $0.1.first?.isNumber == true }) else { return nil }

        var used = Set<Int>()
        // 1. Kind + leading words.
        var kind = Result.Kind.event
        var needsEventWord = true
        if f[0] == "nhac" {
            kind = .reminder
            needsEventWord = false
            used.insert(0)
            var i = 1
            if i < f.count, pronouns.contains(f[i]) { used.insert(i); i += 1 }
            if i < f.count, ["la", "de"].contains(f[i]) { used.insert(i) }
        } else if let prefix = eventPrefixes.first(where: { f.starts(with: $0) }) {
            needsEventWord = false
            used.formUnion(0..<prefix.count)
            var i = prefix.count
            if i + 1 < f.count, f[i] == "cho", pronouns.contains(f[i + 1]) { used.formUnion([i, i + 1]); i += 2 }
        }

        // 2. Exactly one time.
        guard let time = findTime(f) else { return nil }
        used.formUnion(time.span)
        var anchors = Set(time.span)                              // a bare "mai" counts only next to the time / period
        if let before = time.span.first.map({ $0 - 1 }), before >= 0, ["luc", "vao"].contains(f[before]) {
            used.insert(before)
            if before - 1 >= 0, f[before - 1] == "vao" { used.insert(before - 1) }   // "vào lúc"
        }

        // 3. Day part right after the time, or before a day word ("sáng mai", "chiều nay").
        var period: String?
        let after = (time.span.last ?? 0) + 1
        if after < f.count, periods.contains(f[after]) {
            period = f[after]; used.insert(after); anchors.insert(after)
        }
        // 4. Day.
        var dayOffset: Int?
        func setDay(_ value: Int, _ indexes: [Int]) -> Bool {
            guard dayOffset == nil else { return false }       // two day words → ambiguous
            dayOffset = value
            used.formUnion(indexes)
            return true
        }
        for i in f.indices where !used.contains(i) {
            switch f[i] {
            case "hom" where i + 1 < f.count && f[i + 1] == "nay":
                guard setDay(0, [i, i + 1]) else { return nil }
            case "ngay" where i + 1 < f.count && f[i + 1] == "mai":
                guard setDay(1, [i, i + 1]) else { return nil }
            case "ngay" where i + 1 < f.count && ["kia", "mot"].contains(f[i + 1]):
                guard setDay(2, [i, i + 1]) else { return nil }
            case let p where periods.contains(p) && i + 1 < f.count && ["mai", "nay"].contains(f[i + 1]):
                guard period == nil || period == p, setDay(f[i + 1] == "mai" ? 1 : 0, [i, i + 1]) else { return nil }
                period = p
            case "mai" where i > 0 && NameNormalizer.kinship.contains(f[i - 1]):
                return nil                                       // "chị Mai": a name, not tomorrow
            case "mai" where anchors.contains(i - 1) || anchors.contains(i + 1):
                guard setDay(1, [i]) else { return nil }
            default: break
            }
        }
        // A "mai" / "nay" / period word left over could be a name ("chị Mai") or a second time → let the AI decide.
        let leftover = f.indices.filter { !used.contains($0) }
        guard !leftover.contains(where: { ["mai", "nay", "sang", "trua", "chieu", "dem", "gio", "phut", "tieng"].contains(f[$0]) })
        else { return nil }

        // 5. Date.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date: Date
        var confidence = 1.0
        switch time.value {
        case .relative(let minutes):
            guard dayOffset == nil, period == nil else { return nil }
            date = now.addingTimeInterval(TimeInterval(minutes * 60))
        case .clock(let hour, let minute):
            guard let resolved = hour24(hour, period: period) else { return nil }
            let h = resolved.hour
            confidence = resolved.guessed ? 0.6 : 1
            let day = calendar.date(byAdding: .day, value: dayOffset ?? 0, to: calendar.startOfDay(for: now)) ?? now
            guard let at = calendar.date(bySettingHour: h, minute: minute, second: 0, of: day), at > now else {
                return nil                                       // passed today: tomorrow or a mistake? the AI asks
            }
            date = at
        }

        // 6. Title (+ location for events): the words left, in order, connectors trimmed.
        var titleTokens = leftover.map { tokens[$0] }
        var locationTokens: [Token] = []
        if kind == .event, let at = titleTokens.firstIndex(where: { ["o", "tai"].contains($0.folded) }) {
            locationTokens = Array(titleTokens[(at + 1)...])
            titleTokens = Array(titleTokens[..<at])
        }
        // Leading connectors only: folded, a last word like "chợ" / "lá" looks like "cho" / "la".
        while let first = titleTokens.first, connectors.contains(first.folded) { titleTokens.removeFirst() }
        while let last = titleTokens.last, ["luc", "vao"].contains(last.folded) { titleTokens.removeLast() }
        guard (1...8).contains(titleTokens.count), locationTokens.count <= 8 else { return nil }
        let titleFolded = titleTokens.map(\.folded)
        if needsEventWord {
            guard eventWords.contains(where: { titleFolded.starts(with: $0) }) else { return nil }
        }
        let title = capitalized(titleTokens.map(\.original).joined(separator: " "))
        let location = locationTokens.isEmpty ? nil : locationTokens.map(\.original).joined(separator: " ")
        return Result(kind: kind, title: title, date: iso(date, timeZone), dateConfidence: confidence, location: location)
    }

    // MARK: - Time

    private enum TimeValue { case clock(hour: Int, minute: Int), relative(minutes: Int) }
    private struct TimeMatch { let span: [Int]; let value: TimeValue }

    /// One time expression; a second one (or "kém") → nil.
    private static func findTime(_ f: [String]) -> TimeMatch? {
        var found: TimeMatch?
        var i = 0
        while i < f.count {
            var match: TimeMatch?
            if let n = Int(f[i]), i + 2 < f.count, ["phut", "tieng", "gio"].contains(f[i + 1]), f[i + 2] == "nua" {
                guard (1...600).contains(n) else { return nil }
                match = TimeMatch(span: [i, i + 1, i + 2], value: .relative(minutes: f[i + 1] == "phut" ? n : n * 60))
            } else if let hm = compact(f[i]) {                               // "8h", "8g", "20h30"
                let h = hm.hour
                var span = [i]
                var minute = hm.minute
                let m = hm.minute
                if m == nil, i + 1 < f.count, f[i + 1] == "ruoi" { minute = 30; span.append(i + 1) }
                match = TimeMatch(span: span, value: .clock(hour: h, minute: minute ?? 0))
            } else if let h = Int(f[i]), i + 1 < f.count, ["gio", "h", "g"].contains(f[i + 1]) {
                var span = [i, i + 1]
                var minute = 0
                if i + 2 < f.count, let m = Int(f[i + 2]), (0...59).contains(m) {
                    minute = m; span.append(i + 2)
                    if i + 3 < f.count, f[i + 3] == "phut" { span.append(i + 3) }
                } else if i + 2 < f.count, f[i + 2] == "ruoi" {
                    minute = 30; span.append(i + 2)
                }
                match = TimeMatch(span: span, value: .clock(hour: h, minute: minute))
            }
            if let match {
                guard found == nil else { return nil }                       // two times → AI
                if case .clock(let h, let m) = match.value, !(0...23).contains(h) || !(0...59).contains(m) { return nil }
                found = match
                i = (match.span.last ?? i) + 1
            } else {
                i += 1
            }
        }
        return found
    }

    /// "8h" / "8g" / "8h30" → (8, nil) / (8, 30).
    private static func compact(_ token: String) -> (hour: Int, minute: Int?)? {
        guard let m = token.wholeMatch(of: /(\d{1,2})[hg](\d{2})?/), let h = Int(m.output.1) else { return nil }
        return (h, m.output.2.flatMap { Int($0) })
    }

    /// parse.v6: sáng 05–10, trưa 11–12, chiều 13–17, tối 18–21, đêm 22–04; no day part: 6–11 morning, 12 noon,
    /// 1–5 afternoon (both guessed → confidence 0.6). Returns nil when the pair makes no sense ("3 giờ sáng" is fine).
    static func hour24(_ hour: Int, period: String?) -> (hour: Int, guessed: Bool)? {
        switch period {
        case "sang": return (0...11).contains(hour) ? (hour, false) : nil
        case "trua": return [11, 12].contains(hour) ? (hour, false) : (1...2).contains(hour) ? (hour + 12, false) : nil
        case "chieu": return (1...6).contains(hour) ? (hour + 12, false) : (12...18).contains(hour) ? (hour, false) : nil
        case "toi": return (6...11).contains(hour) ? (hour + 12, false) : (18...23).contains(hour) ? (hour, false) : nil
        case "dem": return (9...11).contains(hour) ? (hour + 12, false) : (21...23).contains(hour) ? (hour, false) : nil
        default:
            if (13...23).contains(hour) { return (hour, false) }
            if hour == 12 { return (12, false) }
            if (6...11).contains(hour) { return (hour, true) }
            if (1...5).contains(hour) { return (hour + 12, true) }
            return nil
        }
    }

    // MARK: - Words (folded)

    private static let pronouns: Set<String> = ["toi", "minh", "em", "con"]
    private static let periods: Set<String> = ["sang", "trua", "chieu", "toi", "dem"]
    private static let connectors: Set<String> = ["luc", "vao", "la", "de"]
    private static let eventPrefixes: [[String]] = [["dat", "lich", "hen"], ["tao", "lich", "hen"], ["dat", "lich"],
                                                    ["tao", "lich"], ["them", "lich"], ["len", "lich"], ["ghi", "lich"],
                                                    ["lich", "hen"]]
    /// Without a "đặt lịch" verb, only these clearly are events ("mai 3 giờ chiều họp").
    private static let eventWords: [[String]] = [["hop"], ["kham"], ["di", "kham"], ["di", "hop"], ["lich", "hop"]]
    /// Words that need the AI: recurrence, relative alerts, weekdays / dates, edit / delete, "or" / "and then", lunar.
    private static let rejected: Set<String> = ["moi", "hang", "lap", "truoc", "xoa", "sua", "huy", "doi", "hoan", "xong",
                                                "tuan", "thu", "cuoi", "thang", "am", "ram", "mung", "kem", "sau",
                                                "hoac", "va", "roi", "nhung", "nhieu", "khong", "chua", "hoi"]

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    private static func iso(_ date: Date, _ timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return f.string(from: date)
    }
}

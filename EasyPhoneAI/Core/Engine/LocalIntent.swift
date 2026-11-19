import Foundation

/// Requests the phone understands by itself, without `/v1/parse` (D-313, owner 2026-11-18): faster (~0.1 s instead
/// of ~2 s), no unit spent, works offline. Only short, unambiguous phrases; anything with a time, a number,
/// FaceTime / video or extra content still goes to the LLM. Nothing runs before S04 / "Xác nhận" (D-100).
enum LocalIntent: Equatable, Sendable {
    /// S21 (D-304, D-311).
    case checkMail(codesOnly: Bool)
    /// `call.open` with this name as said ("mẹ", "anh Minh"); contacts are resolved on device as usual.
    case call(name: String)
    /// S11 for this day (`YYYY-MM-DD`), like `viewCalendar` (D-294).
    case calendarDay(String)
    /// `place.open` to a saved label: "home" / "work".
    case directions(label: String)
    /// S12.
    case reminders
    /// D-320: a reminder / event with a clear time (`LocalSchedule`).
    case schedule(LocalSchedule.Result)

    /// The first rule that matches, or nil (→ `/v1/parse`).
    static func match(_ text: String, now: Date = .now, timeZone: TimeZone = .current) -> LocalIntent? {
        if isCheckMail(text) { return .checkMail(codesOnly: wantsCode(text)) }
        if let schedule = LocalSchedule.match(text, now: now, timeZone: timeZone) { return .schedule(schedule) }
        let words = Words(text)
        guard !words.folded.isEmpty, words.folded.count <= 9 else { return nil }
        if let name = callName(words) { return .call(name: name) }
        if let offset = calendarOffset(words) { return .calendarDay(day(now, plus: offset, in: timeZone)) }
        if let label = directionsLabel(words) { return .directions(label: label) }
        if isReminders(words) { return .reminders }
        return nil
    }

    // MARK: - Check mail (2.5c)

    /// "có thư mới không", "kiểm tra mail", "xem mã gửi về", "mã OTP"… Writing / sending / replying never matches.
    static func isCheckMail(_ text: String) -> Bool {
        let t = " " + NameNormalizer.normalize(text) + " "
        guard !compose.contains(where: t.contains) else { return false }
        return checks.contains(where: t.contains)
    }

    /// "xem mã gửi về", "mã OTP", "đọc mã xác nhận" → codes only. Bare "mã" is not enough (folded it is also "mà").
    static func wantsCode(_ text: String) -> Bool {
        let t = " " + NameNormalizer.normalize(text) + " "
        guard !compose.contains(where: t.contains) else { return false }
        return codes.contains(where: t.contains)
    }

    // Diacritics folded by `NameNormalizer` ("thư mới" → "thu moi", "mã" → "ma").
    private static let compose = [" soan ", " viet ", " gui cho ", " gui mail ", " gui email ", " gui thu ",
                                  " gui ma ", " tra loi ", " nhan cho ", " nhan tin ", " chuyen tiep "]
    private static let checks = [" thu moi ", " mail moi ", " email moi ", " gmail co gi ", " kiem tra mail ",
                                 " kiem tra email ", " kiem tra gmail ", " kiem tra thu ", " ma xac nhan ",
                                 " ma xac minh ", " ma xac thuc ", " ma otp ", " otp ", " ma gui ve ",
                                 " ma dang nhap ", " doc ma ", " xem ma "]
    private static let codes = [" ma xac ", " ma otp ", " otp ", " ma gui ve ", " ma dang nhap ", " doc ma ",
                                " xem ma ", " lay ma ", " ma code ", " code "]

    // MARK: - Words

    /// The request as words: original (kept for names, with diacritics) and folded (for matching), punctuation
    /// dropped, polite openers ("Khoai ơi", "hãy", "giúp tôi") and closers ("nhé", "đi", "với") removed.
    struct Words {
        var original: [String]
        var folded: [String]

        init(_ text: String) {
            let raw = text.components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
                .filter { !$0.isEmpty }
            var pairs = raw.map { ($0, NameNormalizer.normalize($0)) }
            while let first = pairs.first?.1, Self.openers.contains(first) { pairs.removeFirst() }
            // Two-word closers first ("giúp tôi", "giúp mình"), then single words. "nha" / "mình" / "tôi" alone are
            // NOT closers: folded they are also "nhà" and the name "Minh".
            var trimmed = true
            while trimmed {
                trimmed = false
                if pairs.count >= 2, Self.closerPairs.contains([pairs[pairs.count - 2].1, pairs[pairs.count - 1].1]) {
                    pairs.removeLast(2)
                    trimmed = true
                } else if let last = pairs.last?.1, Self.closers.contains(last) {
                    pairs.removeLast()
                    trimmed = true
                }
            }
            original = pairs.map(\.0)
            folded = pairs.map(\.1)
        }

        static let openers: Set<String> = ["e", "khoai", "oi", "hay", "giup", "dum", "lam", "on", "ban", "vui", "long"]
        static let closers: Set<String> = ["nhe", "di", "voi", "ngay", "luon", "duoc", "khong", "a"]
        static let closerPairs: Set<[String]> = [["giup", "toi"], ["giup", "minh"], ["dum", "toi"], ["ho", "toi"],
                                                 ["cho", "toi"], ["nhe", "ban"], ["di", "ban"]]

        func starts(with prefix: [String]) -> Bool { folded.starts(with: prefix) }
        var joined: String { folded.joined(separator: " ") }
    }

    // MARK: - Call

    /// "gọi (điện (thoại)) (cho) {name}" → the name as said (1–4 words, no digits, no time / FaceTime / app words).
    static func callName(_ w: Words) -> String? {
        guard w.starts(with: ["goi"]) else { return nil }
        var i = 1
        if w.folded.dropFirst(i).starts(with: ["dien", "thoai"]) { i += 2 } else if w.folded.dropFirst(i).first == "dien" { i += 1 }
        if w.folded.dropFirst(i).first == "cho" { i += 1 }
        let name = Array(w.original.dropFirst(i))
        let folded = Array(w.folded.dropFirst(i))
        guard (1...4).contains(name.count), !folded.contains(where: notAName.contains),
              !name.joined().contains(where: \.isNumber) else { return nil }
        return name.joined(separator: " ")
    }

    private static let notAName: Set<String> = ["luc", "gio", "phut", "sang", "trua", "chieu", "toi", "dem", "mai",
                                                  "nay", "facetime", "video", "zalo", "messenger", "so", "lai", "sau",
                                                  "nhac", "nho", "hen", "lich"]

    // MARK: - Calendar day

    /// "xem lịch (trình) hôm nay / ngày mai / ngày kia", "lịch ngày mai", "mai (tôi) có lịch gì" → 0 / 1 / 2.
    static func calendarOffset(_ w: Words) -> Int? {
        let t = " " + w.joined + " "
        guard t.contains(" lich ") else { return nil }
        let create = [" dat ", " tao ", " them ", " xoa ", " sua ", " doi ", " hen ", " nhac ", " huy "]
        guard !create.contains(where: t.contains) else { return nil }
        let asks = w.starts(with: ["xem"]) || w.starts(with: ["lich"]) || w.starts(with: ["cho", "toi", "xem"])
            || t.contains(" co lich gi ") || t.contains(" co lich nao ")
        guard asks else { return nil }
        if t.contains(" hom nay ") { return 0 }
        if t.contains(" ngay kia ") || t.contains(" ngay mot ") { return 2 }
        if t.contains(" ngay mai ") || t.contains(" mai ") { return 1 }
        return t.contains(" hom ") ? nil : (w.starts(with: ["xem", "lich"]) && w.folded.count <= 3 ? 0 : nil)
    }

    static func day(_ now: Date, plus days: Int, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(byAdding: .day, value: days, to: now) ?? now
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Directions

    /// "chỉ đường / dẫn đường (về / đến / tới) nhà | công ty | chỗ làm" → "home" / "work".
    static func directionsLabel(_ w: Words) -> String? {
        let verbs: [[String]] = [["chi", "duong"], ["dan", "duong"], ["duong"]]
        guard let verb = verbs.first(where: w.starts(with:)) else { return nil }
        var rest = Array(w.folded.dropFirst(verb.count))
        if let first = rest.first, ["ve", "den", "toi", "qua"].contains(first) { rest.removeFirst() }
        switch rest {
        case ["nha"], ["nha", "minh"], ["nha", "toi"]: return "home"
        case ["cong", "ty"], ["cho", "lam"], ["noi", "lam", "viec"]: return "work"
        default: return nil
        }
    }

    // MARK: - Reminders list

    static func isReminders(_ w: Words) -> Bool {
        ["xem loi nhac", "danh sach loi nhac", "loi nhac cua", "loi nhac cua toi", "toi co loi nhac gi", "co loi nhac gi",
         "xem nhac nho", "xem cac loi nhac", "mo loi nhac"].contains(w.joined)
    }
}

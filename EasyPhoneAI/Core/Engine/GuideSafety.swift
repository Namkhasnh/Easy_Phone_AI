import Foundation

/// 4H (D-337 – D-340): on-device rules for "Khoai hướng dẫn". Pure, unit-tested.
enum GuideSafety {
    static let mask = "•••"

    // MARK: - Is it a "how do I…" question? (4H.3)

    // TODO(spec): D-337 does not say how S03 tells a guide question from a task; these word lists are Claude's choice.
    /// A guide question ("làm sao gửi ảnh Zalo", "chỉ tôi cách tăng cỡ chữ"), or a curated phone-settings topic said
    /// without a question word ("tăng cỡ chữ"). Asks to *do* something ("nhắn Zalo cho Minh: …") stay tasks.
    static func isGuideQuestion(_ text: String, library: GuideLibrary = .bundled) -> Bool {
        let t = " " + GuideLibrary.fold(text) + " "
        guard t.count > 2, !notGuide.contains(where: t.contains) else { return false }
        if howTo.contains(where: t.contains) { return true }
        if t.contains(" o dau "), whereWords.contains(where: t.contains) { return true }
        if t.hasSuffix(" sao "), t.split(separator: " ").count > 2 { return true }   // "… chuyển sao?" (4H.7)
        // Settings topics are never a task the app can run (no Zalo / call / contact entry here).
        guard let entry = library.match(text, includeUnverified: true) else { return false }
        return entry.id.hasPrefix("iphone.") || entry.id.hasPrefix("camera.")
    }

    private static let howTo = [" lam sao ", " lam the nao ", " the nao ", " nhu the nao ", " ra sao ", " cach ",
                                " huong dan ", " chi toi ", " chi minh ", " chi cho toi ", " chi giup ",
                                " bam vao dau ", " bam o dau ", " cham vao dau ", " bang cach nao ", " khong biet "]
    /// "… ở đâu" is a guide only about the phone's screen; "nhà thuốc ở đâu" is a place.
    private static let whereWords = [" bam ", " cham ", " nut ", " cai dat ", " xem ", " tim ", " nam ", " nhap ",
                                     " tat ", " chinh "]
    /// "chỉ đường", "cách đây 2 ngày", "không biết đường" are not guide questions.
    private static let notGuide = [" chi duong ", " duong den ", " duong toi ", " duong di ", " duong ve ", " cach day ",
                                   " cach nha ", " khong biet duong "]

    // MARK: - Money (D-339)

    /// D-339 on-device keyword check (the same words as the backend `MONEY_WORDS`); money = this **or** the AI flag.
    static func isMoneyRelated(_ text: String) -> Bool {
        let t = " " + GuideLibrary.fold(text) + " "
        return moneyWords.contains { t.contains(" \($0) ") }
    }

    static let moneyWords = [
        "chuyen tien", "chuyen khoan", "otp", "ma xac nhan", "ma xac thuc", "ngan hang", "thanh toan", "vi dien tu",
        "momo", "zalopay", "zalo pay", "vnpay", "nap tien", "rut tien", "vay", "so du", "tai khoan ngan hang", "the atm",
        "the tin dung", "mua hang", "dat hang", "shopee", "lazada", "tiki", "tiktok shop", "dau tu", "trung thuong",
        "qr", "ma qr", "tra tien", "gui tien", "tai khoan", "trieu", "muon tien", "tien coc", "nop phi",
    ]

    // MARK: - Masking (D-340)

    /// Before anything leaves the phone: digit runs that look like an OTP (4 – 8), an account (9 – 16) or a card
    /// (13 – 19, spaces / dashes allowed) and "mật khẩu / pass … <word>" → `•••`. Amounts ("500 nghìn", "2 triệu",
    /// "200k", "100.000 tiền"), dates ("25/11/2026") and years ("năm 2026") are kept. Same rules as the backend `mask_secrets`.
    static func masked(_ text: String) -> String {
        let ns = NSMutableString(string: text)
        password.replaceMatches(in: ns, range: NSRange(location: 0, length: ns.length), withTemplate: "$1$2\(mask)")
        digits.replaceMatches(in: ns, range: NSRange(location: 0, length: ns.length), withTemplate: mask)
        return ns as String
    }

    private static let amountAfter = #"(?!\d|[ ]?(?:đ|đồng|dong|k|nghìn|ngàn|triệu|tr|vnd|vnđ|tiền|tien)\b)"#   // "482913 đọc" is not "đ"
    nonisolated(unsafe) private static let digits = try! NSRegularExpression(   // immutable after init, thread-safe
        pattern: #"(?<![\d/])(?<!năm )(?<!nam )(?:(?:\d[ \-.]?){4,19}\d|\d{4})"# + amountAfter, options: [.caseInsensitive])
    nonisolated(unsafe) private static let password = try! NSRegularExpression(  // immutable after init, thread-safe
        pattern: #"\b(mật khẩu|mat khau|password|pass|mã pin|ma pin|pin)\b(\s*(?:là|la|:)?\s*)(\S+)"#,
        options: [.caseInsensitive])
}

/// Hands-free words on the guide screen (D-312, D-337): "tiếp" moves on.
enum GuideVoiceCommand: Equatable, Sendable {
    case next, repeatStep, previous, stop, other

    static func classify(_ text: String) -> GuideVoiceCommand {
        let words = GuideLibrary.fold(text).split(separator: " ")
        guard !words.isEmpty, words.count <= 6 else { return .other }
        let t = " " + words.joined(separator: " ") + " "
        if [" thoi ", " dung ", " huy ", " dung lai ", " ket thuc "].contains(where: t.contains) { return .stop }
        if [" quay lai ", " buoc truoc ", " lui lai "].contains(where: t.contains) { return .previous }
        if [" noi lai ", " doc lai ", " nhac lai ", " lap lai "].contains(where: t.contains) { return .repeatStep }
        if [" tiep ", " tiep theo ", " xong ", " roi ", " duoc roi ", " ok ", " buoc tiep ", " sang buoc "]
            .contains(where: t.contains) { return .next }
        return .other
    }
}

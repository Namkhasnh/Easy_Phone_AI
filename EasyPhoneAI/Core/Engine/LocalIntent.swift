import Foundation

/// Requests the phone understands by itself, without `/v1/parse` (owner 2026-11-18: faster, and no unit is spent).
/// Only unambiguous phrases; anything else still goes to the backend LLM.
// TODO(decision): not in DECISIONS / ARCHITECTURE §6.2 (every request goes through `/v1/parse`); owner asked for speed.
enum LocalIntent {
    /// "có thư mới không", "kiểm tra mail", "xem mã gửi về", "mã OTP"… → S21 (same as `checkMail`, D-304, D-311).
    /// Writing / sending / replying ("soạn mail cho…", "gửi thư cho…", "trả lời…") is never matched.
    static func isCheckMail(_ text: String) -> Bool {
        let t = " " + NameNormalizer.normalize(text) + " "
        guard !compose.contains(where: t.contains) else { return false }
        return checks.contains(where: t.contains)
    }

    // Diacritics folded by `NameNormalizer` ("thư mới" → "thu moi", "mã" → "ma").
    private static let compose = [" soan ", " viet ", " gui cho ", " gui mail ", " gui email ", " gui thu ",
                                  " gui ma ", " tra loi ", " nhan cho ", " nhan tin ", " chuyen tiep "]
    private static let checks = [" thu moi ", " mail moi ", " email moi ", " gmail co gi ", " kiem tra mail ",
                                 " kiem tra email ", " kiem tra gmail ", " kiem tra thu ", " ma xac nhan ",
                                 " ma xac minh ", " ma xac thuc ", " ma otp ", " otp ", " ma gui ve ",
                                 " ma dang nhap ", " doc ma ", " xem ma "]
}

import Foundation

/// D-322 (owner 2026-11-19): fixes iOS speech-to-text gluing numbers together, before the text is shown or used.
/// Only unambiguous cases: weekdays are "thứ 2" … "thứ 7", so "thứ 79h" can only be "thứ 7 9h" and "thứ 710 giờ" only
/// "thứ 7 10 giờ". Anything else is left as heard (the user still sees and can edit the text).
enum SpeechCleanup {
    private static let gluedWeekday = try! NSRegularExpression(
        pattern: #"\b(thứ|thu)\s*([2-7])(\d{1,2})(?=\s*(h|g|giờ|gio|:|\b))"#, options: [.caseInsensitive])

    static func fix(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return gluedWeekday.stringByReplacingMatches(in: text, range: range, withTemplate: "$1 $2 $3")
    }
}

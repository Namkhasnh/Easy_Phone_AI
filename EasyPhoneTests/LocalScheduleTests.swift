import Foundation
import Testing
@testable import EasyPhoneAI

/// D-320 — reminders / events with a clear time, understood on the phone. Now = Thu 19/11/2026 10:00 (+07:00).
@Suite("Local schedule (D-320)")
struct LocalScheduleTests {
    static let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    static let now = ISO8601DateFormatter().date(from: "2026-11-19T10:00:00+07:00")!

    static func m(_ text: String) -> LocalSchedule.Result? { LocalSchedule.match(text, now: now, timeZone: tz) }

    @Test(arguments: [
        ("Nhắc tôi uống thuốc lúc 8 giờ tối", "Uống thuốc", "2026-11-19T20:00:00+07:00", 1.0),
        ("nhắc tôi 8 giờ sáng mai uống thuốc", "Uống thuốc", "2026-11-20T08:00:00+07:00", 1.0),
        ("Khoai ơi nhắc mình gọi cho mẹ lúc 7h30 tối nhé", "Gọi cho mẹ", "2026-11-19T19:30:00+07:00", 1.0),
        ("nhắc tôi tắt bếp 30 phút nữa", "Tắt bếp", "2026-11-19T10:30:00+07:00", 1.0),
        ("nhắc tôi 2 tiếng nữa đi đón con", "Đi đón con", "2026-11-19T12:00:00+07:00", 1.0),
        ("nhắc tôi nộp tiền điện lúc 3 giờ", "Nộp tiền điện", "2026-11-19T15:00:00+07:00", 0.6),
        ("nhắc tôi chiều mai 4 giờ rưỡi đi chợ", "Đi chợ", "2026-11-20T16:30:00+07:00", 1.0),
        ("nhắc tôi lấy đồ giặt lúc 20:15", "Lấy đồ giặt", "2026-11-19T20:15:00+07:00", 1.0),
        ("nhắc tôi tưới cây ngày mai lúc 9 giờ", "Tưới cây", "2026-11-20T09:00:00+07:00", 0.6),
        ("nhắc tôi 9 giờ tối nay uống thuốc", "Uống thuốc", "2026-11-19T21:00:00+07:00", 1.0),          // audit 11-27
        ("nhắc tôi gọi mẹ lúc 2 giờ chiều nay", "Gọi mẹ", "2026-11-19T14:00:00+07:00", 1.0),
    ])
    func reminders(text: String, title: String, date: String, confidence: Double) throws {
        let r = try #require(Self.m(text), "\(text)")
        #expect(r.kind == .reminder && r.title == title && r.date == date && r.dateConfidence == confidence, "\(text) → \(r)")
    }

    @Test(arguments: [
        ("mai 3 giờ chiều họp", "Họp", "2026-11-20T15:00:00+07:00", nil as String?),
        ("đặt lịch khám răng 9 giờ sáng ngày mai ở nha khoa Kim", "Khám răng", "2026-11-20T09:00:00+07:00", "nha khoa Kim"),
        ("tạo lịch họp nhóm lúc 14h ở công ty", "Họp nhóm", "2026-11-19T14:00:00+07:00", "công ty"),
        ("đặt lịch cho tôi ăn tối với gia đình 7 giờ tối mai", "Ăn tối với gia đình", "2026-11-20T19:00:00+07:00", nil),
    ])
    func events(text: String, title: String, date: String, location: String?) throws {
        let r = try #require(Self.m(text), "\(text)")
        #expect(r.kind == .event && r.title == title && r.date == date && r.location == location, "\(text) → \(r)")
    }

    /// Everything the phone must NOT guess: the AI handles it (weekday, date, recurring, alert, edit, ambiguity…).
    @Test(arguments: [
        "nhắc tôi uống thuốc 8 giờ sáng mỗi ngày",          // recurring
        "thứ Bảy tuần này 9 giờ đi khám răng",              // weekday
        "đặt lịch khám răng ngày 25 lúc 9 giờ",             // numeric date
        "đặt lịch họp 9 giờ mai, nhắc trước 1 tiếng",       // alert
        "nhắc tôi uống thuốc",                              // no time
        "nhắc tôi chiều nay đi chợ",                        // day part only
        "nhắc tôi gọi chị Mai lúc 8 giờ tối",               // "Mai" is a name
        "nhắc tôi 7 giờ sáng đi tập",                       // 07:00 already passed today, no day given
        "xóa lời nhắc uống thuốc 8 giờ tối",                // delete
        "đổi lịch họp sang 3 giờ chiều mai",                // edit
        "nhắc tôi 8 giờ tối uống thuốc và 9 giờ tối đi ngủ", // two times
        "3 giờ chiều mai",                                  // no title
        "mai 3 giờ chiều đi siêu thị",                      // not clearly an event, no "nhắc"
        "gọi cho mẹ lúc 8 giờ tối",                         // a call, not a reminder
        "nhắc tôi 9 giờ kém 15 tối gọi bố",                 // "kém"
        "nhắc tôi mùng 1 âm lịch đi chùa lúc 6 giờ sáng",   // lunar
        "nhắc tôi 25 giờ uống nước",                        // impossible hour
    ])
    func goesToTheAI(text: String) {
        #expect(Self.m(text) == nil, "\(text) → \(String(describing: Self.m(text)))")
    }

    @Test func wiredIntoLocalIntentBeforeTheCalendarView() {
        // "lịch họp mai 3 giờ chiều" used to open the calendar of tomorrow (calendarOffset); now it is an event draft.
        guard case .schedule(let s) = LocalIntent.match("lịch họp mai 3 giờ chiều", now: Self.now, timeZone: Self.tz) else {
            Issue.record("not a schedule"); return
        }
        #expect(s.kind == .event && s.date == "2026-11-20T15:00:00+07:00")
        #expect(LocalIntent.match("xem lịch ngày mai", now: Self.now, timeZone: Self.tz) == .calendarDay("2026-11-20"))
    }

    @Test func hour24FollowsParsePromptV6() {
        #expect(LocalSchedule.hour24(3, period: "chieu")! == (15, false))
        #expect(LocalSchedule.hour24(8, period: "toi")! == (20, false))
        #expect(LocalSchedule.hour24(12, period: "trua")! == (12, false))
        #expect(LocalSchedule.hour24(8, period: nil)! == (8, true))
        #expect(LocalSchedule.hour24(2, period: nil)! == (14, true))
        #expect(LocalSchedule.hour24(9, period: "chieu") == nil)
    }
}

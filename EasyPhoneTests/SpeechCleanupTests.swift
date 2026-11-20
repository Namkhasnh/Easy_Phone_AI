import Testing
@testable import EasyPhoneAI

/// D-322 — iOS speech glues "thứ 7" and the hour ("Thứ 79h sáng", owner's iPhone 2026-11-19).
@Suite("Speech cleanup (D-322)")
struct SpeechCleanupTests {
    @Test(arguments: [
        ("Thứ 79h sáng đi khám răng", "Thứ 7 9h sáng đi khám răng"),
        ("thứ 710 giờ họp", "thứ 7 10 giờ họp"),
        ("Thứ 28:30 đi chợ", "Thứ 2 8:30 đi chợ"),
        ("thứ 59 giờ tối", "thứ 5 9 giờ tối"),
        ("thu 39h", "thu 3 9h"),
    ])
    func splitsAGluedWeekdayAndHour(heard: String, fixed: String) {
        #expect(SpeechCleanup.fix(heard) == fixed)
    }

    @Test(arguments: ["Thứ 7 9h sáng", "thứ Bảy 9 giờ", "nhắc tôi 8 giờ tối", "gọi số 0901234567",
                      "thứ 8 cái", "phòng 79", "thứ tự 12"])
    func leavesEverythingElse(text: String) {
        #expect(SpeechCleanup.fix(text) == text)
    }
}

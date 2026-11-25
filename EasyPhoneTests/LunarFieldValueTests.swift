import Foundation
import Testing
@testable import EasyPhoneAI

/// 4L.3 (D-332): `lunarDate` encoding `[YYYY-]MM-DD[L][THH:mm]` — same cases as `backend/tests/test_lunar_field.py`.
@Suite("Lunar field value (D-332)")
struct LunarFieldValueTests {
    @Test(arguments: ["03-10", "06-01L", "00-15", "00-01T06:00", "2027-03-10", "12-30T18:30", "01-01", "N0-15", "N1-01T06:00", "NX-05"])
    func valid(value: String) throws {
        let v = try #require(LunarFieldValue(value), "\(value)")
        #expect(v.encoded == value)                                         // round trip
        #expect(Validator.isEncoded(value, as: .lunarDate))
    }

    @Test(arguments: ["3-10", "13-01", "03-31", "03-00", "00-15L", "2027-00-15", "03-10T24:00", "03-10T06:60", "10/3", "",
                      "2027-03-10L ", "1700-03-10", "03-10t06:00", "N2-15", "N0-15L",
                      "2027-N1-15", "NX-31"])
    func invalid(value: String) {
        #expect(LunarFieldValue(value) == nil, "\(value)")
        #expect(!Validator.isEncoded(value, as: .lunarDate))
    }

    @Test func parts() throws {
        let v = try #require(LunarFieldValue("2027-06-01LT06:30"))
        #expect(v == LunarFieldValue(year: 2027, month: 6, day: 1, isLeap: true, hour: 6, minute: 30))
        #expect(try #require(LunarFieldValue("00-15")).isEveryMonth)
    }

    @Test func display() {
        func show(_ v: String) -> String? {
            FieldFormatter.display(Field(id: "lunarDate", type: .lunarDate, value: v), timeZoneId: "Asia/Ho_Chi_Minh")
        }
        #expect(show("03-10") == "10/3 âm lịch")
        #expect(show("06-01L") == "1/6 nhuận âm lịch")
        #expect(show("2027-03-10") == "10/3/2027 âm lịch")
        #expect(show("00-15T06:00") == "Ngày 15 hằng tháng (âm lịch) lúc 06:00")
        #expect(show("N0-15") == "Ngày 15 tháng này (âm lịch)")
        #expect(show("N1-01") == "Ngày 1 tháng sau (âm lịch)")
        #expect(show("NX-05T07:00") == "Ngày 5 âm lịch sắp tới lúc 07:00")
        #expect(FieldFormatter.option(fieldId: "lunarRecurrence", value: "yearly") == "Hằng năm")
    }
}

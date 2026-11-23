import Foundation
import Testing
@testable import EasyPhoneAI

/// 4H.2 (D-338): the curated guide set and its on-device match (no AI call, no unit).
@Suite("Curated guides (4H.2)")
struct GuideLibraryTests {
    static let library = GuideLibrary.bundled

    func id(_ q: String) -> String? { Self.library.match(q, includeUnverified: true)?.id }

    @Test func bundledSetIsWellFormed() {
        let guides = Self.library.guides
        #expect((15...20).contains(guides.count))
        #expect(Set(guides.map(\.id)).count == guides.count)                           // ids unique
        for g in guides {
            #expect((2...12).contains(g.steps.count), "\(g.id)")
            #expect(!g.title.isEmpty && !g.match.isEmpty, "\(g.id)")
            // Patterns are already folded, else they never match.
            for phrase in g.match.flatMap({ $0 }) + g.exclude {
                #expect(GuideLibrary.fold(phrase) == phrase, "\(g.id): \(phrase)")
            }
            // D-339 / D-340: never a verdict, never "give the OTP".
            for s in g.steps {
                let t = GuideLibrary.fold(s.text + " " + (s.hint ?? ""))
                #expect(!t.contains("an toan") && !t.contains("khong phai lua dao"), "\(g.id)")
                #expect(!t.contains("doc ma otp cho") && !t.contains("gui ma otp"), "\(g.id)")
            }
        }
    }

    @Test(arguments: [
        ("Làm sao gửi ảnh qua Zalo cho con?", "zalo.sendPhoto"),
        ("gửi tấm ảnh này qua zalo thế nào", "zalo.sendPhoto"),
        ("Cách gọi video Zalo", "zalo.videoCall"),
        ("gọi điện qua Zalo làm sao", "zalo.voiceCall"),
        ("nhắn tin Zalo thế nào", "zalo.message"),
        ("chữ trên điện thoại nhỏ quá, làm sao cho to hơn", "iphone.textSize"),
        ("tăng cỡ chữ", "iphone.textSize"),
        ("làm chữ đậm hơn", "iphone.boldText"),
        ("Kết nối Wi-Fi thế nào?", "iphone.wifi"),
        ("chụp màn hình sao vậy", "iphone.screenshot"),
        ("bật đèn pin ở đâu", "iphone.flashlight"),
        ("chuông nhỏ quá không nghe", "iphone.volume"),
        ("xoá ảnh trong máy", "iphone.deletePhoto"),
        ("điện thoại hết pin nhanh quá", "iphone.lowPower"),
        ("cập nhật iPhone như thế nào", "iphone.update"),
        ("máy báo đầy bộ nhớ", "iphone.storage"),
        ("kết nối tai nghe bluetooth", "iphone.bluetooth"),
        ("lưu số điện thoại vào danh bạ", "phone.saveContact"),
        ("quét mã QR bằng điện thoại", "camera.scanQR"),
        ("Hướng dẫn chuyển tiền qua app ngân hàng", "bank.transfer"),
        ("mua hàng trên Shopee thế nào", "shop.shopeeOrder"),
    ])
    func matches(question: String, expected: String) {
        #expect(id(question) == expected, "\(question)")
    }

    /// Scam situations, other topics and unclear questions go to the AI (situation warnings, D-339).
    @Test(arguments: [
        "Có người gọi điện bảo con bị tai nạn, chuyển tiền gấp thế nào",
        "Nhân viên ngân hàng xin mã OTP, tôi xem ở đâu",
        "Công an bảo chuyển tiền vào tài khoản tạm giữ",
        "chuyển tiền qua Zalo",
        "nhắn tin Zalo cho anh Minh bảo chuyển khoản",
        "cập nhật Zalo",
        "giá vàng hôm nay",
        "đặt báo thức",
        "",
    ])
    func goesToTheAI(question: String) {
        #expect(id(question) == nil, "\(question)")
    }

    @Test func kinshipWordIsNotAPhoto() {
        #expect(id("nhắn tin Zalo cho anh Minh") == "zalo.message")
    }

    @Test func unverifiedEntriesAreSkippedWhenAsked() throws {
        let entry = try #require(Self.library.guides.first)
        let lib = GuideLibrary(schemaVersion: 1, version: 1, guides: [entry])
        let q = entry.match[0].joined(separator: " ")
        #expect(lib.match(q, includeUnverified: true)?.id == entry.id)
        #expect(entry.verified || lib.match(q, includeUnverified: false) == nil)
    }

    @Test func tieGivesNoGuess() throws {
        let a = try #require(Self.library.guides.first { $0.id == "iphone.wifi" })
        let twin = GuideLibrary.Entry(id: "twin", title: "x", verified: true, isMoneyRelated: false,
                                      match: a.match, exclude: [], steps: a.steps)
        let lib = GuideLibrary(schemaVersion: 1, version: 1, guides: [a, twin])
        #expect(lib.match("wifi", includeUnverified: true) == nil)
    }

    @Test func curatedAndAIGuidesShareOneModel() throws {
        let entry = try #require(Self.library.guides.first { $0.id == "bank.transfer" })
        #expect(entry.guide.isMoneyRelated && entry.guide.source == .curated(id: "bank.transfer"))
        #expect(GuideResponse.mock.guide?.source == .ai(requestId: "req_01JD4H1GUIDE"))
    }
}

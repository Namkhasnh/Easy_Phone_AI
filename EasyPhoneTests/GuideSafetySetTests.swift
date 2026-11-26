import Foundation
import Testing
@testable import EasyPhoneAI

/// 4H.7 (D-339, D-340): the shared question set `guide.eval_set.json` (30 phone-use + 20 money, same bytes as the
/// backend tests and live eval) on the phone: every guide question reaches S23, every money question is warned
/// even when the AI says "not money" and gives no warning, nothing secret leaves the phone.
@MainActor
@Suite("Bộ câu hỏi hướng dẫn (4H.7)")
struct GuideSafetySetTests {
    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        let id: String
        let question: String
        let kind: String
        let money: Bool
        var testDescription: String { id }
    }

    private final class BundleToken: Sendable {}
    nonisolated static let cases: [Case] = {
        struct File: Decodable { let cases: [Case] }
        guard let url = Bundle(for: BundleToken.self).url(forResource: "guide.eval_set", withExtension: "json"),
              let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [] }
        return file.cases
    }()
    nonisolated static let guides = cases.filter { $0.kind == "guide" }
    nonisolated static let money = guides.filter(\.money)

    @Test func setHasThirtyPlusTwenty() {
        #expect(Self.guides.filter { !$0.money }.count == 30 && Self.money.count == 20)
    }

    /// S03 / the panel send every guide question to S23, never to a task or the S21 code list.
    @Test(arguments: guides)
    func routesToTheGuide(c: Case) {
        #expect(LocalIntent.match(c.question) == .guide(question: c.question), "\(c.id)")
    }

    /// The on-device keyword check alone (D-339 backup layer) flags every money question and no plain one.
    @Test(arguments: guides)
    func moneyFlagOnTheDevice(c: Case) {
        #expect(GuideSafety.isMoneyRelated(c.question) == c.money, "\(c.id)")
    }

    /// Worst model answer (not money, no warning): S23 still shows the 3 fixed warnings and "Gọi cho con", and the
    /// question sent holds no OTP / account digits.
    @Test(arguments: money)
    func moneyIsAlwaysWarned(c: Case) async {
        let careless = GuideResponse(schemaVersion: 1, requestId: "r", title: "x",
                                     steps: [.init(text: "Mở app.", hint: nil), .init(text: "Làm theo app.", hint: nil)],
                                     isMoneyRelated: false, scamWarnings: [], unsupported: nil)
        let api = MockAPIClient(guide: .success(careless))
        let vm = GuideViewModel(question: c.question, api: api)
        await vm.load()
        #expect(vm.isMoneyRelated, "\(c.id)")
        for key in GuideViewModel.fixedWarningKeys {
            #expect(vm.spokenWarnings.contains(UserMessage(key: key).text), "\(c.id)")
        }
        if let sent = api.guideCalls.first?.request.question {
            #expect(sent.range(of: #"\d{4,}"#, options: .regularExpression) == nil, "\(c.id): \(sent)")
        }
    }

    // MARK: - Masking (D-340)

    @Test(arguments: [
        ("Mã OTP 482913 ngân hàng gửi về", "Mã OTP ••• ngân hàng gửi về"),
        ("mã OTP 4829", "mã OTP •••"),
        ("OTP: 482-913", "OTP: •••"),
        ("mã xác nhận là 12 34 56", "mã xác nhận là •••"),
        ("Mã OTP của bạn là 789012. Không chia sẻ", "Mã OTP của bạn là •••. Không chia sẻ"),
        ("STK 1903 5678 9012 34", "STK •••"),
        ("số thẻ 9704-0000-1234-5678", "số thẻ •••"),
        ("chuyển vào số tài khoản 0123456789 của bạn nó", "chuyển vào số tài khoản ••• của bạn nó"),
        ("mật khẩu: Abc@123 quên rồi", "mật khẩu: ••• quên rồi"),
        ("pass là 123456", "pass là •••"),
        ("mã PIN 1234", "mã PIN •••"),
        // Kept: amounts, dates, years, short numbers.
        ("chuyển 1.500.000 đồng cho con", "chuyển 1.500.000 đồng cho con"),
        ("rút 2.000.000 vnđ", "rút 2.000.000 vnđ"),
        ("nạp 100.000 tiền điện thoại", "nạp 100.000 tiền điện thoại"),
        ("mượn 5 triệu", "mượn 5 triệu"),
        ("20tr", "20tr"),
        ("hẹn 25/11/2026", "hẹn 25/11/2026"),
        ("năm 2026", "năm 2026"),
        ("lãi 30% một tháng", "lãi 30% một tháng"),
    ])
    func masks(input: String, expected: String) {
        #expect(GuideSafety.masked(input) == expected)
    }
}

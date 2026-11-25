import Foundation

/// `POST /v1/guide` request (API_CONTRACT §7.5, D-337). `question` = the user's words with OTP / account / card /
/// password already masked on device (D-340, 4H.4).
struct GuideRequest: Codable, Sendable, Hashable {
    var schemaVersion: Int = 1
    var question: String
    var locale: String
}

/// `POST /v1/guide` response: a step-by-step guide the user follows (Khoai never taps, D-337). `scamWarnings` only when
/// `isMoneyRelated`; the fixed warnings and "Gọi cho con" are app strings (D-339). `unsupported = "notAGuide"` →
/// "Chưa hỗ trợ".
struct GuideResponse: Codable, Sendable, Hashable {
    struct Step: Codable, Sendable, Hashable {
        let text: String
        let hint: String?
    }

    let schemaVersion: Int
    let requestId: String
    let title: String?
    let steps: [Step]
    let isMoneyRelated: Bool
    let scamWarnings: [String]
    let unsupported: String?
}

extension GuideResponse {
    /// = `guide.money.response.json` (API_CONTRACT §7.5 example; previews, D-206).
    static let mock = GuideResponse(
        schemaVersion: 1, requestId: "req_01JD4H1GUIDE", title: "Chuyển tiền qua app ngân hàng",
        steps: [
            .init(text: "Trước khi chuyển, hãy gọi thẳng cho con bằng số bạn đã lưu trong Danh bạ.",
                  hint: "Đừng gọi lại số vừa gọi cho bạn."),
            .init(text: "Mở app ngân hàng của bạn trên màn hình chính.", hint: nil),
            .init(text: "Chạm vào nút Chuyển tiền (tên có thể khác).", hint: "Thường nằm ở hàng nút đầu tiên."),
            .init(text: "Nhập số tài khoản người nhận và kiểm tra tên hiện ra.", hint: nil),
            .init(text: "Nhập số tiền, đọc lại một lần rồi chạm Tiếp tục.", hint: nil),
            .init(text: "Nhập mã OTP ngân hàng gửi về điện thoại của bạn vào app.",
                  hint: "Chỉ nhập vào app, không đọc cho ai."),
        ],
        isMoneyRelated: true,
        scamWarnings: [
            "Kẻ gian hay giả làm bệnh viện hoặc thầy cô, báo người nhà bị tai nạn để bạn hoảng và chuyển tiền ngay.",
            "Bệnh viện không yêu cầu chuyển tiền vào tài khoản cá nhân qua điện thoại.",
        ],
        unsupported: nil)
}

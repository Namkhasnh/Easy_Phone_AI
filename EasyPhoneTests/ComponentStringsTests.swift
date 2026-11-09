import Foundation
import Testing
@testable import EasyPhoneAI

/// 1A.10b — DATA_MODEL §8 (state label + icon), UI_SCREENS §10.2 (field labels), §0 rule 2 (format args).
@Suite("Component strings (DATA_MODEL §8, UI_SCREENS §10.2)")
struct ComponentStringsTests {
    static func localized(_ key: String) -> String { String(localized: String.LocalizationValue(key)) }

    @Test func stateLabelsAndIconsPerDataModel8() {
        let expected: [TaskState: (String, String)] = [
            .draft: ("Bản nháp", "square.and.pencil"),
            .needsInfo: ("Cần thêm thông tin", "questionmark.circle"),
            .awaitingApproval: ("Chờ bạn xác nhận", "hand.raised"),
            .processing: ("Đang thực hiện", "hourglass"),
            .prepared: ("Đã chuẩn bị — cần mở %@", "tray.full"),
            .handedOff: ("Cần hoàn tất trong %@", "arrow.up.forward.app"),
            .unknown: ("Chưa rõ kết quả", "exclamationmark.circle"),
            .succeeded: ("Đã xong", "checkmark.circle"),
            .userMarkedDone: ("Bạn đã làm xong", "checkmark.seal"),
            .failed: ("Không thành công", "xmark.octagon"),
            .cancelled: ("Đã hủy", "minus.circle"),
        ]
        #expect(Set(expected.keys) == Set(TaskState.allCases))
        for (state, (label, symbol)) in expected {
            #expect(Self.localized(state.labelKey) == label, "\(state)")
            #expect(state.symbolName == symbol, "\(state)")
        }
    }

    @Test func formatArgsFillPlaceholders() {
        #expect(UserMessage(key: "state.prepared", args: ["Zalo"]).text == "Đã chuẩn bị — cần mở Zalo")
        #expect(UserMessage(key: "state.handedOff", args: ["Điện thoại"]).text == "Cần hoàn tất trong Điện thoại")
        #expect(UserMessage(key: "stepIndicator.label", args: ["1", "2"]).text == "Bước 1/2")
        #expect(UserMessage(key: "a11y.state", args: ["Đã xong"]).text == "Trạng thái: Đã xong")
        #expect(UserMessage(key: "common.empty").text == "Chưa có")
    }

    @Test func everyCatalogFieldHasALabel() {
        for k in FieldCatalog.mvp.kinds {
            for spec in k.fields {
                let key = "field.\(k.kind.rawValue).\(spec.id)"
                #expect(Self.localized(key) != key, "missing \(key)")
            }
        }
        #expect(Self.localized("field.reminder.dueDate") == "Thời gian nhắc")
    }
}

import SwiftUI
import Testing
@testable import EasyPhoneAI

/// D-318 — the app's own text size (S15 Hiển thị).
@MainActor
@Suite("App text size")
struct TextSizeTests {
    @Test func choiceIsSavedAndMapsToDynamicType() {
        let local = MockLocalDataRepository()
        let vm = SettingsViewModel(localData: local, drafts: MockTaskRepository(), auth: MockAuthService())
        #expect(vm.textSize == .system && AppTextSize.system.dynamicTypeSize == nil)   // default: follow iOS
        vm.setTextSize(.xLarge)
        #expect(local.settings().textSize == "xLarge" && vm.textSize == .xLarge)
        #expect(AppTextSize.huge.dynamicTypeSize == .accessibility3)
        #expect(AppTextSize(stored: "unknown") == .system)
        let sizes = AppTextSize.allCases.compactMap(\.dynamicTypeSize)
        #expect(sizes == sizes.sorted())                                            // each step bigger
    }

    @Test func strings() {
        for size in AppTextSize.allCases {
            #expect(UserMessage(key: size.labelKey).text != size.labelKey, "missing \(size.labelKey)")
        }
        #expect(UserMessage(key: "settings.textSize.preview").text.contains("Khoai"))
    }
}

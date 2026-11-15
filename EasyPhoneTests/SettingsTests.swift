import Foundation
import Testing
@testable import EasyPhoneAI

/// 1A.14 — UI_SCREENS S15 / S20, spec §6.10 AC3–AC4, P-40, D-244, D-289.
@MainActor
@Suite("Settings (UI_SCREENS S15)")
struct SettingsTests {
    let local = MockLocalDataRepository()
    let drafts = MockTaskRepository()
    let auth = MockAuthService(initial: .signedIn(userId: MockAuthService.userId))

    func model() -> SettingsViewModel { SettingsViewModel(localData: local, drafts: drafts, auth: auth) }

    @Test func defaultsAndSimpleModeHidesAdvanced() {
        let vm = model()
        #expect(vm.settings.petEnabled)                    // D-289: on by default
        #expect(vm.showsAdvanced)
        vm.settings.simpleMode = true
        #expect(!vm.showsAdvanced)                          // P-40
        #expect(SettingsViewModel.snoozeHours == [5, 6, 7, 8, 9, 10, 11])
    }

    @Test func clearHistoryDeletesClosedDraftsOnly() async {
        let closed = TaskDraft(inputMode: .text, originalInput: "a",
                               steps: [TaskStep(order: 0, kind: .reminder, operation: .create, state: .succeeded)])
        let open = TaskDraft(inputMode: .text, originalInput: "b",
                             steps: [TaskStep(order: 0, kind: .reminder, operation: .create, state: .failed)])
        drafts.save(closed); drafts.save(open)
        let vm = model()
        vm.pendingConfirm = .clearHistory
        await vm.perform(.clearHistory)
        #expect(drafts.draft(closed.id) == nil && drafts.draft(open.id) != nil)   // D-244
        #expect(vm.pendingConfirm == nil)
    }

    @Test func clearMemoryWipesNicknamesAndPlacesKeepsSettings() async {
        local.saveNickname("mẹ", contactId: "C1")
        local.save(SavedPlace(label: "home", name: "Nhà", address: "1", latitude: 0, longitude: 0))
        let vm = model()
        vm.settings.simpleMode = true
        #expect(vm.nicknames.count == 1)
        await vm.perform(.clearMemory)
        #expect(vm.nicknames.isEmpty && local.nicknames().isEmpty && local.savedPlaces().isEmpty)
        #expect(local.settings().simpleMode)
    }

    @Test func signOutKeepsDrafts() async {
        let d = TaskDraft(inputMode: .text, originalInput: "a")
        drafts.save(d)
        await model().perform(.signOut)
        #expect(auth.currentSession == .signedOut)
        #expect(drafts.draft(d.id) != nil)                  // S20: drafts stay on the phone
    }

    // MARK: - 1C.17 nickname rows, S05 snooze hour

    func withContacts(_ access: PermissionStatus) -> SettingsViewModel {
        let contacts = MockContactsService([ContactRecord(id: "C1", givenName: "Lan", middleName: "Thị",
                                                          familyName: "Nguyễn", phoneCount: 1)])
        return SettingsViewModel(localData: local, drafts: drafts, auth: auth,
                                 permissions: MockPermissionManager([.contacts: access]), contacts: contacts)
    }

    @Test func nicknameRowShowsContactName() async {
        let n = local.saveNickname("mẹ", contactId: "C1")
        let vm = withContacts(.granted)
        await vm.loadContactNames()
        let row = vm.nicknameRow(n)
        #expect(row.hasPrefix("mẹ → "))
        #expect(row.contains("Lan"))
    }

    @Test func nicknameRowWithoutContactsAccessOrContactIsNicknameOnly() async {
        let n = local.saveNickname("mẹ", contactId: "C1")
        let gone = local.saveNickname("sếp", contactId: "deleted")
        let denied = withContacts(.denied)
        await denied.loadContactNames()
        #expect(denied.nicknameRow(n) == "mẹ")
        let granted = withContacts(.granted)
        await granted.loadContactNames()
        #expect(granted.nicknameRow(gone) == "sếp")
    }

    @Test func fieldEditorUsesSettingsSnoozeHour() {
        let field = Field(id: "snoozeOption", type: .enumChoice, value: nil)
        let step = TaskStep(order: 0, kind: .reminder, operation: .snooze, fields: [field])
        let editor = FieldEditorViewModel(field: field, step: step, timeZoneId: "Asia/Ho_Chi_Minh",
                                          snoozeMorningHour: 6) { _ in }
        #expect(editor.optionLabel("tomorrowMorning").contains("6"))
    }

    @Test func deleteNickname() {
        let n = local.saveNickname("sếp", contactId: "C2")
        let vm = model()
        vm.deleteNickname(n)
        #expect(vm.nicknames.isEmpty)
    }

    @Test func confirmTexts() {
        #expect(UserMessage(key: SettingsViewModel.Confirm.clearMemory.titleKey).text == "Xóa dữ liệu ghi nhớ?")
        #expect(UserMessage(key: SettingsViewModel.Confirm.signOut.confirmKey).text == "Đăng xuất")
        #expect(UserMessage(key: "settings.snoozeHour.value", args: ["8"]).text == "8 giờ")
    }
}

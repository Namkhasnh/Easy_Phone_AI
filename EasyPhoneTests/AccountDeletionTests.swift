import Foundation
import Testing
@testable import EasyPhoneAI

/// 1G.2 — "Xóa tài khoản" (S20, API_CONTRACT §6.3, ARCHITECTURE §6.6, D-073, D-104, D-108).
@MainActor
@Suite("Account deletion")
struct AccountDeletionTests {
    let repo = MockTaskRepository()
    let local = MockLocalDataRepository()
    let images = MockImageStore()
    let auth = MockAuthService(initial: .signedIn(userId: MockAuthService.userId))

    func model(_ api: MockAPIClient) -> SettingsViewModel {
        SettingsViewModel(localData: local, drafts: repo, auth: auth, api: api, images: images)
    }

    func seed() async throws -> UUID {
        let draft = TaskDraft(inputMode: .text, originalInput: "Nhắc tôi uống thuốc")
        repo.save(draft)
        local.saveNickname("mẹ", contactId: "lan")
        _ = try await images.save(Data([1, 2, 3]), draftId: draft.id)
        return draft.id
    }

    @Test func confirmedDeletionWipesThePhoneAndSignsOut() async throws {
        let api = MockAPIClient()
        let id = try await seed()
        let vm = model(api)
        vm.pendingConfirm = .deleteAccount
        #expect(api.deleteAccountCalls == 0)                                   // nothing before the tap (D-108)
        #expect(SettingsViewModel.Confirm.deleteAccount.confirmKey == "confirm.deleteAccount.yes")
        await vm.perform(.deleteAccount)
        #expect(api.deleteAccountCalls == 1)
        #expect(repo.draft(id) == nil && local.nicknames().isEmpty && images.stored.isEmpty)
        #expect(auth.currentSession == .signedOut)
        #expect(vm.accountMessage == nil && !vm.deletingAccount)
    }

    @Test func aFailedDeletionKeepsEverything() async throws {
        let api = MockAPIClient()
        api.setDeleteAccount(.failure(.network(.offline)))
        let id = try await seed()
        let vm = model(api)
        await vm.perform(.deleteAccount)
        #expect(repo.draft(id) != nil && !local.nicknames().isEmpty && !images.stored.isEmpty)   // D-104
        #expect(auth.currentSession != .signedOut)
        #expect(vm.accountMessage == UserMessage(key: "error.network.offline"))
    }

    @Test func strings() {
        for key in ["settings.deleteAccount", "confirm.deleteAccount.title", "confirm.deleteAccount.body",
                    "confirm.deleteAccount.subNote", "confirm.deleteAccount.yes", "confirm.deleteAccount.no",
                    "confirm.deleteAccount.progress"] {
            #expect(UserMessage(key: key).text != key, "missing \(key)")
        }
    }
}

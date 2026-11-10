import Foundation
import Observation

/// S15 Settings shell (UI_SCREENS S15, spec §6.10 AC3–AC4). Settings autosave on change (D-104).
@Observable @MainActor final class SettingsViewModel {
    /// Destructive confirms (S20, `ConfirmSheet`). Delete always needs a tap (D-108).
    enum Confirm: String, Identifiable, Sendable {
        case clearHistory, clearMemory, signOut
        var id: String { rawValue }
        var titleKey: String { "confirm.\(rawValue).title" }
        var bodyKey: String { "confirm.\(rawValue).body" }
        var confirmKey: String { self == .signOut ? "confirm.signOut.yes" : "confirm.delete" }
    }

    let settings: AppSettings
    private(set) var nicknames: [Nickname] = []
    var pendingConfirm: Confirm?

    private let localData: any LocalDataRepository
    private let drafts: any TaskRepository
    private let auth: any AuthService

    init(localData: any LocalDataRepository, drafts: any TaskRepository, auth: any AuthService) {
        self.localData = localData
        self.drafts = drafts
        self.auth = auth
        settings = localData.settings()
        nicknames = localData.nicknames()
    }

    static let snoozeHours = Array(5...11)            // picker 5–11 (S15)
    static let mapsApps = ["appleMaps", "googleMaps"] // DATA_MODEL §4 `mapsApp` options

    /// Simple mode hides ★ rows (P-40).
    var showsAdvanced: Bool { !settings.simpleMode }

    var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return UserMessage(key: "settings.version", args: [version]).text
    }

    func save() { localData.saveSettings() }

    func deleteNickname(_ nickname: Nickname) {
        localData.delete(nickname)
        nicknames = localData.nicknames()
    }

    /// Runs the confirmed destructive action.
    func perform(_ confirm: Confirm) async {
        pendingConfirm = nil
        switch confirm {
        case .clearHistory: drafts.deleteClosed()                 // closed drafts only (D-244)
        case .clearMemory:
            localData.wipeMemory()                                // nicknames + saved places (§5)
            nicknames = []
        case .signOut: await auth.signOut()                       // drafts stay on the phone (S20)
        }
    }
}

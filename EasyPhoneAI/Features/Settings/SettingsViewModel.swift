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
    /// Contact name per nickname id for "mẹ → Nguyễn Thị Lan" (S15). Read on device only, never sent (D-056).
    private(set) var contactNames: [UUID: String] = [:]
    var pendingConfirm: Confirm?
    /// S15 "Quyền truy cập": one row per capability (UI_SCREENS S15, §10.4). Re-read when the app is active again,
    /// because the user may have changed it in iOS Settings.
    private(set) var permissionStatuses: [(capability: Capability, status: PermissionStatus)] = []

    private let localData: any LocalDataRepository
    private let drafts: any TaskRepository
    private let auth: any AuthService
    private let tts: any TTSService
    private let permissions: any PermissionManager
    private let contacts: any ContactsService

    init(localData: any LocalDataRepository, drafts: any TaskRepository, auth: any AuthService,
         tts: any TTSService = MockTTSService(), permissions: any PermissionManager = MockPermissionManager(),
         contacts: any ContactsService = MockContactsService()) {
        self.permissions = permissions
        self.contacts = contacts
        self.localData = localData
        self.drafts = drafts
        self.auth = auth
        self.tts = tts
        settings = localData.settings()
        nicknames = localData.nicknames()
        refreshPermissions()
    }

    /// Contact names for the nickname rows. Only with Contacts access (never asks, D-185); a deleted / not shared
    /// contact keeps the nickname alone.
    func loadContactNames() async {
        guard permissions.status(.contacts).isUsable else { contactNames = [:]; return }
        var names: [UUID: String] = [:]
        for nickname in nicknames {
            if let match = try? await contacts.contact(id: nickname.contactId) { names[nickname.id] = match.displayName }
        }
        contactNames = names
    }

    /// "mẹ → Nguyễn Thị Lan", or the nickname alone when the contact name is unknown.
    func nicknameRow(_ nickname: Nickname) -> String {
        guard let name = contactNames[nickname.id] else { return nickname.nickname }
        // TODO(spec): UI_SCREENS S15 shows the row only by example; key `settings.nicknames.row` added (PROGRESS §5.2).
        return UserMessage(key: "settings.nicknames.row", args: [nickname.nickname, name]).text
    }

    /// Reads only; never asks (D-185: requests happen on first use, after S18).
    func refreshPermissions() {
        permissionStatuses = Capability.allCases.map { ($0, permissions.status($0)) }
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

    /// "Nghe thử" (S15): speaks `settings.voice.sample` at the chosen rate. Works even when voice is off (explicit tap).
    func testVoice() async {
        await tts.speak(UserMessage(key: "settings.voice.sample").text, rate: settings.speechRate)
    }

    /// Leaving Settings or starting a new sample cuts the voice off (spec §6.2 AC5).
    func stopVoice() { tts.stop() }

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

import Foundation
import Observation

/// S15 Settings shell (UI_SCREENS S15, spec §6.10 AC3–AC4). Settings autosave on change (D-104).
@Observable @MainActor final class SettingsViewModel {
    /// Destructive confirms (S20, `ConfirmSheet`). Delete always needs a tap (D-108).
    enum Confirm: String, Identifiable, Sendable {
        case clearHistory, clearMemory, signOut, gmailDisconnect
        var id: String { rawValue }
        var titleKey: String { "confirm.\(rawValue).title" }
        var bodyKey: String { "confirm.\(rawValue).body" }
        var confirmKey: String {
            switch self {
            case .signOut: "confirm.signOut.yes"
            case .gmailDisconnect: "confirm.gmailDisconnect.yes"
            case .clearHistory, .clearMemory: "confirm.delete"
            }
        }
    }

    let settings: AppSettings
    private(set) var nicknames: [Nickname] = []
    /// Contact name per nickname id for "mẹ → Nguyễn Thị Lan" (S15). Read on device only, never sent (D-056).
    private(set) var contactNames: [UUID: String] = [:]
    var pendingConfirm: Confirm?
    /// S15 "Quyền truy cập": one row per capability (UI_SCREENS S15, §10.4). Re-read when the app is active again,
    /// because the user may have changed it in iOS Settings.
    private(set) var permissionStatuses: [(capability: Capability, status: PermissionStatus)] = []
    /// S15 "Kết nối" (API_GMAIL §3, D-306): the one connected Gmail account, if any.
    private(set) var gmailAccount: GmailAccount?
    private(set) var gmailBusy = false
    /// Last connect / disconnect failure, shown under the Gmail row.
    private(set) var gmailMessage: UserMessage?
    /// `GMAIL_CLIENT_ID` is set (Config/Secrets.xcconfig); otherwise the row says "Gmail — sắp có".
    let gmailAvailable: Bool

    private let localData: any LocalDataRepository
    private let drafts: any TaskRepository
    private let auth: any AuthService
    private let tts: any TTSService
    private let permissions: any PermissionManager
    private let contacts: any ContactsService
    private let photoLibrary: any PhotoLibraryService
    private let gmail: any GmailService

    init(localData: any LocalDataRepository, drafts: any TaskRepository, auth: any AuthService,
         tts: any TTSService = MockTTSService(), permissions: any PermissionManager = MockPermissionManager(),
         contacts: any ContactsService = MockContactsService(),
         photoLibrary: any PhotoLibraryService = MockPhotoLibraryService(),
         gmail: any GmailService = MockGmailService(), gmailAvailable: Bool = true) {
        self.gmail = gmail
        self.gmailAvailable = gmailAvailable
        self.photoLibrary = photoLibrary
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

    /// D-301 "Lưu ảnh chụp vào Ảnh": turning it on is the user's own request, so the add-only alert comes now (the row's
    /// note explains it); a "no" turns the switch back off.
    func savePhotosChanged() async {
        if settings.savePhotos, !(await photoLibrary.requestAddAccess()) {
            settings.savePhotos = false
        }
        save()
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
        case .gmailDisconnect: await disconnectGmail()
        }
    }

    // MARK: - Gmail (API_GMAIL §2–§3)

    func loadGmail() async {
        guard gmailAvailable else { return }
        do {
            gmailAccount = try await gmail.accounts().first
        } catch {
            // Offline etc.: keep what we showed; the row still offers "Kết nối Gmail".
        }
    }

    /// "Kết nối Gmail" / "Kết nối lại Gmail": Google consent sheet → backend. Closing the sheet is not an error.
    func connectGmail() async {
        guard !gmailBusy else { return }
        gmailBusy = true
        gmailMessage = nil
        defer { gmailBusy = false }
        do {
            gmailAccount = try await gmail.connect()
        } catch is CancellationError {
        } catch {
            gmailMessage = Self.gmailFailure(error)
        }
    }

    private func disconnectGmail() async {
        guard let account = gmailAccount else { return }
        gmailBusy = true
        gmailMessage = nil
        defer { gmailBusy = false }
        do {
            try await gmail.disconnect(accountId: account.accountId)
            gmailAccount = nil
        } catch {
            gmailMessage = Self.gmailFailure(error)
        }
    }

    /// "Gmail: khanh@gmail.com" (S15).
    var gmailAccountText: String? {
        gmailAccount.map { UserMessage(key: "settings.gmail.account", args: [$0.email]).text }
    }

    static func gmailFailure(_ error: any Error) -> UserMessage {
        guard let error = error as? AppError else { return UserMessage(key: "settings.gmail.failed") }
        switch error {
        case .network: return UserMessage(key: "error.network.offline")
        case .api(_, _, let details, _) where details?.reason == "missingScope":
            // TODO(spec): API_GMAIL §3.1 gives the words, UI_SCREENS S15 no key → `settings.gmail.missingScope`.
            return UserMessage(key: "settings.gmail.missingScope")
        case .api(let code, _, _, _) where code.hasPrefix("gmail_"):
            return UserMessage(key: "error.\(code)")
        default:
            // TODO(spec): no generic connect-failure key in UI_SCREENS S15 → `settings.gmail.failed`.
            return UserMessage(key: "settings.gmail.failed")
        }
    }
}

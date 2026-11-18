import AppIntents
import Foundation

/// D-170 – D-172, ARCHITECTURE §2.2: the one shared entry intent. Siri ("Ê Khoai"), the Action Button, Back Tap
/// (Shortcuts), Spotlight and the Control Center control all run it; it opens the app and starts listening (S03).
struct StartListeningIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.listen.title"
    static let description = IntentDescription("intent.listen.desc")
    static let openAppWhenRun = true

    @Dependency private var appState: AppState

    @MainActor
    func perform() async throws -> some IntentResult {
        appState.startListeningRequested = true
        return .result()
    }
}

/// App Shortcuts (UI_SCREENS §7, D-288): available at once in Shortcuts, Spotlight, Siri and the Action Button
/// picker, with no setup by the user.
// TODO(spec): 1E.2 — Vietnamese phrases need iOS 18.4+ Siri in Vietnamese + `AppShortcuts.xcstrings`; checked on device.
struct EasyPhoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartListeningIntent(),
                    phrases: ["Ê \(.applicationName)", "\(.applicationName)", "Mở \(.applicationName)",
                              "Nói với \(.applicationName)", "Open \(.applicationName)", "Talk to \(.applicationName)"],
                    shortTitle: "intent.listen.title",
                    systemImageName: "mic.fill")
    }
}

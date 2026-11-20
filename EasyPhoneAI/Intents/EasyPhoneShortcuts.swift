import AppIntents
import Foundation

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
        // D-325: the panel over the current screen (Back Tap → this shortcut). No Vietnamese Siri phrase works yet.
        AppShortcut(intent: AskKhoaiIntent(),
                    phrases: ["Hỏi \(.applicationName)", "Ask \(.applicationName)"],
                    shortTitle: "intent.ask.title",
                    systemImageName: "bubble.left.fill")
    }
}

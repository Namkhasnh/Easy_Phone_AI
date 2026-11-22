import AppIntents
import Foundation

/// App Shortcuts (UI_SCREENS §7, D-288): available at once in Shortcuts, Spotlight, Siri and the Action Button
/// picker, with no setup by the user. The app ships Vietnamese only (development language `vi`), so these phrases are
/// Vietnamese Siri phrases (iOS 18.4+, D-012). `.applicationName` also matches the alternative name "Khoai"
/// (`INAlternativeAppNames`, Config/Info.plist). More ways to say each phrase: `Resources/AppShortcuts.xcstrings`.
// D-328 (owner 2026-11-22): no English phrases — an `en` localization would turn system UI in the app English.
struct EasyPhoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartListeningIntent(),
                    phrases: ["Ê \(.applicationName)", "\(.applicationName)", "Mở \(.applicationName)",
                              "Nói với \(.applicationName)"],
                    shortTitle: "intent.listen.title",
                    systemImageName: "mic.fill")
        // D-325: the panel over the current screen (Back Tap / Action Button → this shortcut).
        AppShortcut(intent: AskKhoaiIntent(),
                    phrases: ["Hỏi \(.applicationName)", "Nhờ \(.applicationName)"],
                    shortTitle: "intent.ask.title",
                    systemImageName: "bubble.left.fill")
    }
}

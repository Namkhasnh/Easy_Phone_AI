import AppIntents
import Foundation
import Testing
@testable import EasyPhoneAI

/// 1E.1 / 1E.3 — the shared entry intent (D-170 – D-172): Siri, Action Button, Back Tap, widgets → listening.
@MainActor
@Suite("Entry points (D-170 – D-172)")
struct EntryPointTests {
    // `perform()` is not called here: the test host app already registered its AppState with AppDependencyManager,
    // and a second registration crashes the host. Checked on the iPhone (Siri / Action Button / Back Tap).
    @Test func intentOpensTheApp() {
        #expect(StartListeningIntent.openAppWhenRun)
    }

    @Test func shortcutsAndStrings() {
        #expect(EasyPhoneShortcuts.appShortcuts.count == 1)
        for key in ["intent.listen.title", "intent.listen.desc"] {
            #expect(UserMessage(key: key).text != key, "missing \(key)")
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let schemes = (info["CFBundleURLTypes"] as? [[String: Any]] ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains("easyphone"))                                   // easyphone://listen (D-172)
        let names = (info["INAlternativeAppNames"] as? [[String: Any]] ?? []).compactMap { $0["INAlternativeAppName"] as? String }
        #expect(names == ["Khoai"])                                              // D-288
    }
}

import AppIntents
import Foundation
import Testing
@testable import EasyPhoneAI

/// 1E.1 / 1E.3 — the shared entry intent (D-170 – D-172): Siri, Action Button, Back Tap, widgets → listening.
@MainActor
@Suite("Entry points (D-170 – D-172)")
struct EntryPointTests {
    @Test func intentOpensTheAppAndAsksToListen() async throws {
        #expect(StartListeningIntent.openAppWhenRun)
        let previous = ListenRequests.onRequest
        defer { ListenRequests.onRequest = previous }
        var asked = 0
        ListenRequests.onRequest = { asked += 1 }
        _ = try await StartListeningIntent().perform()
        #expect(asked == 1)
    }

    @Test func shortcutsAndStrings() {
        #expect(EasyPhoneShortcuts.appShortcuts.count == 2)                      // listen + "Hỏi Khoai" (D-325)
        for key in ["intent.listen.title", "intent.listen.desc", "intent.ask.title", "intent.ask.desc", "intent.ask.prompt"] {
            #expect(UserMessage(key: key).text != key, "missing \(key)")
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let schemes = (info["CFBundleURLTypes"] as? [[String: Any]] ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains("easyphone"))                                   // easyphone://listen (D-172)
        let names = (info["INAlternativeAppNames"] as? [[String: Any]] ?? []).compactMap { $0["INAlternativeAppName"] as? String }
        #expect(names == ["Khoai"])                                              // D-288
    }

    /// 1E.2 (D-012, D-288): Vietnamese Siri phrases ship in `AppShortcuts.xcstrings`; every way to say one keeps the
    /// app name (Apple rule, also matches "Khoai"), and the D-288 calls "Ê Khoai" / "Khoai" are there.
    @Test func vietnamesePhrasesShip() throws {
        let path = try #require(Bundle.main.path(forResource: "AppShortcuts", ofType: "strings", inDirectory: nil,
                                                 forLocalization: "vi"))
        let table = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
        let phrases = Set(table.values)
        #expect(phrases.count >= 12)
        #expect(phrases.allSatisfy { $0.contains("${applicationName}") })
        for p in ["Ê ${applicationName}", "${applicationName}", "${applicationName} ơi", "Mở ${applicationName}",
                  "Nói với ${applicationName}", "Hỏi ${applicationName}"] {
            #expect(phrases.contains(p), "missing \(p)")
        }
    }
}

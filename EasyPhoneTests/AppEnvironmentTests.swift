import Foundation
import Testing
@testable import EasyPhoneAI

@Suite("AppEnvironment (D-206)")
struct AppEnvironmentTests {
    @Test func mockNeverPointsAtARealServer() {
        let env = AppEnvironment.mock()
        #expect(env.config == .mock)
        #expect(env.config.apiBaseURL.host()?.hasSuffix(".invalid") == true)
        #expect(env.config.supabaseURL?.host()?.hasSuffix(".invalid") == true)
    }

    /// 1C.18a — ARCHITECTURE §13: `-uiTestScenario uiTest` selects the scenario; nothing / unknown → live wiring.
    @Test func uiTestScenarioFromLaunchArguments() throws {
        let defaults = try #require(UserDefaults(suiteName: "uitest-args-\(UUID())"))
        #expect(MockScenario.fromLaunchArguments(defaults) == nil)
        defaults.set("bogus", forKey: "uiTestScenario")
        #expect(MockScenario.fromLaunchArguments(defaults) == nil)
        defaults.set("uiTest", forKey: "uiTestScenario")
        #expect(MockScenario.fromLaunchArguments(defaults) == .uiTest)
    }

    @MainActor
    @Test func uiTestScenarioIsSignedInWithAllPermissionsAndOneMinh() async throws {
        let env = AppEnvironment.mock(.uiTest)
        #expect((env.auth as? MockAuthService)?.currentSession == .signedIn(userId: MockAuthService.userId))
        #expect(Capability.allCases.allSatisfy { env.permissions.status($0) == .granted })
        let matches = try await env.contacts.match(name: "anh Minh")
        #expect(matches.count == 1)
    }
}

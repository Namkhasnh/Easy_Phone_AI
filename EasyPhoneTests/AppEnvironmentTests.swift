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
}

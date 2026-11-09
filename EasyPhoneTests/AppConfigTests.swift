import Foundation
import Testing
@testable import EasyPhoneAI

@Suite("AppConfig (0.7, D-207)")
struct AppConfigTests {
    private func info(api: String? = "https://api.example.com",
                      supabase: String? = "https://ref.supabase.co",
                      anon: String? = "anon") -> [String: Any] {
        var d: [String: Any] = [:]
        d[AppConfig.apiBaseURLKey] = api
        d[AppConfig.supabaseURLKey] = supabase
        d[AppConfig.supabaseAnonKeyKey] = anon
        return d
    }

    @Test func parsesValidValues() throws {
        let c = try AppConfig(infoDictionary: info())
        #expect(c.apiBaseURL.absoluteString == "https://api.example.com")
        #expect(c.supabaseURL?.absoluteString == "https://ref.supabase.co")
        #expect(c.supabaseAnonKey == "anon")
    }

    @Test func localHTTPBackendIsAllowed() throws {
        let c = try AppConfig(infoDictionary: info(api: "http://127.0.0.1:8000"))
        #expect(c.apiBaseURL.port == 8000)
    }

    @Test func emptySupabaseValuesBecomeNil() throws {
        let c = try AppConfig(infoDictionary: info(supabase: "", anon: "  "))
        #expect(c.supabaseURL == nil)
        #expect(c.supabaseAnonKey == nil)
    }

    @Test func missingAPIKeyThrows() {
        #expect(throws: AppConfig.LoadError.missing(AppConfig.apiBaseURLKey)) {
            try AppConfig(infoDictionary: info(api: nil))
        }
    }

    @Test func unexpandedBuildSettingCountsAsMissing() {
        #expect(throws: AppConfig.LoadError.missing(AppConfig.apiBaseURLKey)) {
            try AppConfig(infoDictionary: info(api: "$(API_BASE_URL)"))
        }
    }

    @Test(arguments: ["ftp://api.example.com", "api.example.com", "https://"])
    func invalidAPIURLThrows(raw: String) {
        #expect(throws: AppConfig.LoadError.invalidURL(AppConfig.apiBaseURLKey)) {
            try AppConfig(infoDictionary: info(api: raw))
        }
    }

    @Test func invalidSupabaseURLThrows() {
        #expect(throws: AppConfig.LoadError.invalidURL(AppConfig.supabaseURLKey)) {
            try AppConfig(infoDictionary: info(supabase: "not a url"))
        }
    }
}

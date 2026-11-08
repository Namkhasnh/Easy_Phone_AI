import Foundation

/// Build-time configuration read from Info.plist, filled from `Config/*.xcconfig` (D-207, D-208).
/// Only the API base URL, the Supabase URL and the Supabase **anon** key may ship in the app (D-051).
struct AppConfig: Sendable, Hashable {
    let apiBaseURL: URL
    /// `nil` until `Config/Secrets.xcconfig` is filled (item 0.8). `AuthService` live requires it (0.9).
    let supabaseURL: URL?
    /// `nil` until `Config/Secrets.xcconfig` is filled (item 0.8). `AuthService` live requires it (0.9).
    let supabaseAnonKey: String?

    enum LoadError: Error, Equatable {
        /// Key missing or an unexpanded `$(…)`: the target's xcconfig / Info.plist File is not set.
        case missing(String)
        case invalidURL(String)
    }

    static let apiBaseURLKey = "APIBaseURL"
    static let supabaseURLKey = "SupabaseURL"
    static let supabaseAnonKeyKey = "SupabaseAnonKey"

    init(apiBaseURL: URL, supabaseURL: URL?, supabaseAnonKey: String?) {
        self.apiBaseURL = apiBaseURL
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
    }

    /// Parses an Info.plist dictionary. Empty Supabase values become `nil`; a missing or bad API URL throws.
    init(infoDictionary info: [String: Any]) throws(LoadError) {
        guard let rawAPI = Self.value(info, Self.apiBaseURLKey) else {
            throw .missing(Self.apiBaseURLKey)
        }
        guard let api = Self.httpURL(rawAPI) else { throw .invalidURL(Self.apiBaseURLKey) }

        var supabase: URL?
        if let rawSupabase = Self.value(info, Self.supabaseURLKey) {
            guard let url = Self.httpURL(rawSupabase) else { throw .invalidURL(Self.supabaseURLKey) }
            supabase = url
        }
        self.init(apiBaseURL: api, supabaseURL: supabase, supabaseAnonKey: Self.value(info, Self.supabaseAnonKeyKey))
    }

    /// The app's own configuration. A failure is a developer setup error, never a user error,
    /// so it stops the app with a message that says what to fix.
    static func fromMainBundle() -> AppConfig {
        do {
            return try AppConfig(infoDictionary: Bundle.main.infoDictionary ?? [:])
        } catch {
            fatalError("AppConfig: \(error). Set the target's configuration files to Config/Debug|Release.xcconfig and Info.plist File to Config/Info.plist.")
        }
    }

    /// Fixed values for previews and tests; never reach a real server.
    static let mock = AppConfig(
        apiBaseURL: URL(string: "https://api.mock.invalid")!,
        supabaseURL: URL(string: "https://supabase.mock.invalid")!,
        supabaseAnonKey: "mock-anon-key"
    )

    private static func value(_ info: [String: Any], _ key: String) -> String? {
        guard let raw = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, !raw.contains("$(") else { return nil }
        return raw
    }

    private static func httpURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host() != nil else { return nil }
        return url
    }
}

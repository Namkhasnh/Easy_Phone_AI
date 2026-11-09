import Foundation

/// Values for the `X-Client-Version` and `Accept-Language` headers (API_CONTRACT §1).
struct ClientInfo: Sendable, Hashable {
    /// `CFBundleShortVersionString(CFBundleVersion)`, e.g. `1.0.0(12)`.
    let clientVersion: String
    /// `vi` or `en` — only selects the backend's fallback `message` language.
    let acceptLanguage: String

    static func fromMainBundle() -> ClientInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return ClientInfo(clientVersion: "\(version)(\(build))",
                          acceptLanguage: language(preferred: Locale.preferredLanguages))
    }

    /// English device → `en`; anything else → `vi` (the app's source language, D-003).
    static func language(preferred: [String]) -> String {
        preferred.first?.lowercased().hasPrefix("en") == true ? "en" : "vi"
    }

    static let mock = ClientInfo(clientVersion: "1.0.0(1)", acceptLanguage: "vi")
}

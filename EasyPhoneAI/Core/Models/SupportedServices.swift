import Foundation

/// DATA_MODEL §10 `Resources/SupportedServices.json` (bundled, read-only). Zalo is verified (D-297); the others stay
/// `verified: false` (D-162): then only copy + guide (S07), never opening the app. `sms` is built in and not listed (D-247).
struct SupportedServices: Codable, Sendable, Hashable {
    struct Service: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let name: String
        let kinds: [String]
        let urlScheme: String?
        let verified: Bool
        /// Vietnamese UI text (S07 steps).
        let guideSteps: [String]
        /// D-297: link that opens the chat with one person, `{phone}` = digits of the E.164 number without "+"
        /// (e.g. `https://zalo.me/{phone}`). Only used when `verified`.
        var chatURL: String? = nil

        /// The person's chat for `e164` ("+84903333444"), or nil (no template, not verified, bad number).
        func chatURL(for e164: String) -> URL? {
            guard verified, let template = chatURL else { return nil }
            let digits = e164.filter(\.isNumber)
            guard digits.count >= 9 else { return nil }
            return URL(string: template.replacingOccurrences(of: "{phone}", with: digits))
        }

        /// The app may be opened only when verified (D-162) and the scheme parses.
        var openURL: URL? { verified ? urlScheme.flatMap(URL.init(string:)) : nil }
    }

    let schemaVersion: Int
    let services: [Service]

    func service(_ id: String) -> Service? { services.first { $0.id == id } }

    /// Ids valid as `sms.channel` besides `sms` (Validator / TaskEngine `serviceIds`, D-247).
    var ids: Set<String> { Set(services.map(\.id)) }

    /// Loaded once from the app bundle; a missing / broken file means "no other channels" (sms still works).
    static let bundled: SupportedServices = {
        guard let url = Bundle.main.url(forResource: "SupportedServices", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(SupportedServices.self, from: data) else {
            return SupportedServices(schemaVersion: 1, services: [])
        }
        return decoded
    }()
}

import Foundation

/// The only error / notice type a View renders (D-265, ARCHITECTURE §2.1).
/// `key` is a `Localizable.xcstrings` key; `args` fill its `%@` placeholders in order (UI_SCREENS §0).
/// Never holds raw error text, `localizedDescription` or a backend `message` (D-184).
struct UserMessage: Sendable, Hashable {
    let key: String
    let args: [String]

    init(key: String, args: [String] = []) {
        self.key = key
        self.args = args
    }
}

extension UserMessage {
    /// Catalog text with `args` filled in order (`%@` placeholders, UI_SCREENS §0 rule 2).
    var text: String {
        let format = String(localized: String.LocalizationValue(key))
        return args.isEmpty ? format : String(format: format, arguments: args)
    }
}

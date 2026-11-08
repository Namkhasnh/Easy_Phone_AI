import Foundation

/// Failure thrown by every service protocol in `Core/Services/` (ARCHITECTURE §9.1).
/// Each case maps to a stable code `<domain>.<reason>` → `error.<code>` in `Localizable.xcstrings` (D-249).
/// `permissionDenied(Capability)` / `limitedAccess(Capability)` are added with `Capability` in 1C.1.
enum ServiceError: Error, Sendable, Hashable {
    case notFound
    /// Feature not usable right now, e.g. `"auth.notSignedIn"`, `"speech.vi.unavailable"`.
    case unavailable(String)
    /// Framework / SDK failure mapped to a stable code, e.g. `"auth.signInFailed"`, `"eventkit.saveFailed"`.
    case framework(code: String)

    /// Stable code used for `error.<code>` lookup and logs.
    var code: String {
        switch self {
        case .notFound: "notFound"
        case .unavailable(let code), .framework(let code): code
        }
    }
}

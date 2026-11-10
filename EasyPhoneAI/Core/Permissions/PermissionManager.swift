import Foundation

/// A device capability that needs the user's permission (ARCHITECTURE §4.4). Raw value = `<c>` in the
/// `perm.<c>.*` / `error.permission.<c>.denied` string keys (UI_SCREENS S18, D-249).
enum Capability: String, Sendable, CaseIterable, Hashable {
    case calendar, reminders, contacts, microphone, speech, camera, photos, location
}

/// iOS authorization collapsed to what the app acts on (ARCHITECTURE §4.4).
/// `limited` = contacts / photos subset; `writeOnly` = calendar add-only access (no conflict check).
enum PermissionStatus: Sendable, Hashable {
    case notDetermined, granted, limited, writeOnly, denied, restricted

    /// The capability can be used now (fully or partly). `notDetermined` is not usable: ask first (D-185, D-249).
    var isUsable: Bool {
        switch self {
        case .granted, .limited, .writeOnly: true
        case .notDetermined, .denied, .restricted: false
        }
    }
}

/// Reads and requests permissions (ARCHITECTURE §4.4). `request` is called **only after** the S18 explainer (D-185).
protocol PermissionManager: Sendable {
    func status(_ capability: Capability) -> PermissionStatus
    func request(_ capability: Capability) async -> PermissionStatus
}

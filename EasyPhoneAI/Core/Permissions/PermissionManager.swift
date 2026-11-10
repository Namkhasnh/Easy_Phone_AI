import Foundation

/// A device capability that needs the user's permission (ARCHITECTURE §4.4). Raw value = `<c>` in the
/// `perm.<c>.*` / `error.permission.<c>.denied` string keys (UI_SCREENS S18, D-249).
enum Capability: String, Sendable, CaseIterable, Hashable {
    case calendar, reminders, contacts, microphone, speech, camera, photos, location
}

/// iOS authorization collapsed to what the app acts on (ARCHITECTURE §4.4).
/// `limited` = contacts / photos subset; `writeOnly` = calendar add-only access (no conflict check).
enum PermissionStatus: String, Sendable, Hashable {
    case notDetermined, granted, limited, writeOnly, denied, restricted

    /// `permStatus.<raw>` (UI_SCREENS §10.4), shown in S15 "Quyền truy cập".
    var labelKey: String { "permStatus.\(rawValue)" }

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

extension Capability {
    /// The capability a step's executor needs at "Xác nhận" (ARCHITECTURE §5.1 step 0), nil = none.
    /// TODO(spec): no doc maps kinds to capabilities. Contacts are read by `DeviceResolver` when the draft is built
    /// (1C.9), not at confirm; `tel://`, the SMS composer and Maps need no permission; OCR asks camera/photos in S09.
    static func required(for kind: TaskKind) -> Capability? {
        switch kind {
        case .calendarEvent: .calendar
        case .reminder: .reminders
        case .call, .sms, .place, .ocr, .emailReply, .ride, .food: nil
        }
    }
}

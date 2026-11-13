import Foundation

/// Phone calls (ARCHITECTURE §4.2, spec §6.7). Only opens `tel://` — iOS asks the user itself; the app can never know
/// whether the call happened, so the step becomes `handedOff`, never `succeeded` (D-102).
protocol CallService: Sendable {
    /// Throws `ServiceError.framework("call.cannotOpen")` when iOS refuses the URL (no phone app, e.g. Simulator / iPad).
    func start(e164: String, type: CallType) async throws
}

/// `call.callType` (D-300). The app cannot pick the SIM line: iOS uses the contact's preferred / default line.
enum CallType: String, Sendable, CaseIterable {
    case phone, facetimeAudio, facetimeVideo

    /// `tel://`, `facetime-audio://`, `facetime://` + E.164.
    func url(_ e164: String) -> URL? {
        switch self {
        case .phone: URL(string: "tel://\(e164)")
        case .facetimeAudio: URL(string: "facetime-audio://\(e164)")
        case .facetimeVideo: URL(string: "facetime://\(e164)")
        }
    }
}

import Foundation

/// Phone calls (ARCHITECTURE §4.2, spec §6.7). Only opens `tel://` — iOS asks the user itself; the app can never know
/// whether the call happened, so the step becomes `handedOff`, never `succeeded` (D-102).
protocol CallService: Sendable {
    /// Throws `ServiceError.framework("call.cannotOpen")` when iOS refuses the URL (no phone app, e.g. Simulator / iPad).
    func start(e164: String) async throws
}

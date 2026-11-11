import UIKit

/// `tel://` through `UIApplication.open` (spec §6.7 AC2).
// TODO(decision): D-014 (UIKit only through representables) vs ARCHITECTURE §4.2 `CallService`: a service cannot open a
// URL without `UIApplication` (SwiftUI's `openURL` exists only inside Views); used here, behind the protocol.
final class LiveCallService: CallService {
    @MainActor func start(e164: String) async throws {
        guard let url = URL(string: "tel://\(e164)"), UIApplication.shared.canOpenURL(url),
              await UIApplication.shared.open(url) else {
            throw ServiceError.framework(code: "call.cannotOpen")
        }
    }
}

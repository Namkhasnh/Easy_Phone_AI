import UIKit

/// `tel://` through `UIApplication.open` (spec §6.7 AC2).
// D-293: `UIApplication.open` is allowed in Live services only (clarifies D-014).
final class LiveCallService: CallService {
    @MainActor func start(e164: String, type: CallType) async throws {
        guard let url = type.url(e164), UIApplication.shared.canOpenURL(url),
              await UIApplication.shared.open(url) else {
            throw ServiceError.framework(code: "call.cannotOpen")
        }
    }
}

import Foundation
import Observation

/// S19 Update required (UI_SCREENS S19). Shown by RootView as a blocking full-screen cover while
/// `AppState.blockingScreen == .clientOutdated` (any API 426, UI_SCREENS §4). There is no way to close it.
@Observable @MainActor final class UpdateRequiredViewModel {
    let minVersion: String

    init(minVersion: String) {
        self.minVersion = minVersion
    }

    /// `update.body` with `{minVersion}` filled in (catalog value uses `%@`).
    var bodyText: String {
        String(format: String(localized: "update.body"), minVersion)
    }

    /// "Mở App Store" (`update.cta`).
    func openStore() {
        // TODO(decision): D-282 vs UI_SCREENS S19 — the thesis build is not on the App Store, so there is no
        // listing to open. The button stays (UI_SCREENS S19) but does nothing; the owner reinstalls from Xcode.
    }
}

import Foundation
import Testing
@testable import EasyPhoneAI

@Suite("S19 UpdateRequiredViewModel (UI_SCREENS S19, §4)")
@MainActor
struct UpdateRequiredViewModelTests {
    @Test func bodyContainsMinVersion() {
        let viewModel = UpdateRequiredViewModel(minVersion: "1.2.0")

        #expect(viewModel.bodyText.contains("1.2.0"))
        #expect(!viewModel.bodyText.contains("%@"))
        #expect(viewModel.bodyText != "update.body")   // key resolved from the catalog
    }

    @Test func emptyMinVersionStillRenders() {
        // APIClient sends "" when the 426 has no `details.minVersion` (TODO(spec) in APIClient).
        let viewModel = UpdateRequiredViewModel(minVersion: "")

        #expect(!viewModel.bodyText.isEmpty)
        #expect(!viewModel.bodyText.contains("%@"))
    }

    @Test func blockingUpdateReachesAppState() async {
        let state = AppState()
        #expect(state.blockingScreen == nil)

        state.blockingScreen = .clientOutdated(minVersion: "1.2.0")

        #expect(state.blockingScreen == .clientOutdated(minVersion: "1.2.0"))
    }
}

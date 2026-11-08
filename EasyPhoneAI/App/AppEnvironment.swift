import SwiftUI

/// Dependency container (ARCHITECTURE §3). Built once in `EasyPhoneApp`, injected via `.environment(\.appEnv, …)`.
/// Service properties are added by the item that builds each service (protocol + Live + Mock, D-206):
/// `auth` (0.9), `api` (0.16), `drafts`/`localData` (1A.9), device services (1C), `speech`/`tts` (1B),
/// `ocr` (1D), `purchases` (1F). Debug vs Release never changes the wiring (D-208).
struct AppEnvironment: Sendable {
    static func live() -> AppEnvironment {
        AppEnvironment()
    }

    static func mock(_ scenario: MockScenario = .default) -> AppEnvironment {
        AppEnvironment()
    }
}

/// Mock scenarios for previews and tests (ARCHITECTURE §13).
/// Cases `offline`, `quotaExceeded`, `permissionDenied`, `threeMinh`, `uiTest` are added with the mocks that need them.
enum MockScenario: Sendable, Hashable {
    case `default`
}

extension EnvironmentValues {
    /// The app root always injects `.live()`; previews inject `.mock(...)`. The default is a mock so a
    /// forgotten injection in a preview never touches real device data.
    @Entry var appEnv: AppEnvironment = .mock()
}

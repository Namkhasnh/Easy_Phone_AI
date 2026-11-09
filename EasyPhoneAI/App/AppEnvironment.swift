import SwiftUI

/// Dependency container (ARCHITECTURE §3). Built once in `EasyPhoneApp`, injected via `.environment(\.appEnv, …)`.
/// Service properties are added by the item that builds each service (protocol + Live + Mock, D-206):
/// `drafts`/`localData` (1A.9), device services (1C), `speech`/`tts` (1B),
/// `ocr` (1D), `purchases` (1F). Debug vs Release never changes the wiring (D-208).
struct AppEnvironment: Sendable {
    /// Build configuration from `Config/*.xcconfig` (0.7, D-207).
    let config: AppConfig
    /// Google sign-in + session (0.9, D-283).
    let auth: any AuthService
    /// Backend `/v1/*` (0.16, API_CONTRACT §10).
    let api: any APIClientProtocol

    static func live() -> AppEnvironment {
        let config = AppConfig.fromMainBundle()
        let auth = LiveAuthService(config: config)
        return AppEnvironment(config: config, auth: auth,
                              api: APIClient(config: config, auth: auth, client: .fromMainBundle()))
    }

    static func mock(_ scenario: MockScenario = .default) -> AppEnvironment {
        AppEnvironment(config: .mock, auth: MockAuthService(), api: MockAPIClient())
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

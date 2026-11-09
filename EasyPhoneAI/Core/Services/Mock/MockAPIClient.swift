import Foundation

/// In-memory `APIClientProtocol` for previews and tests (D-206). Never touches the network.
/// The `.mock` values are kept in code so previews need no fixture files in the app bundle (owner, 0.18 option A);
/// `ContractFixtureTests.mocksEqualFixtures` keeps them equal to `backend/tests/fixtures/contract/` (API_CONTRACT §11).
final class MockAPIClient: APIClientProtocol {
    private let meResult: Result<MeResponse, AppError>
    private let quota = Broadcast<Quota>()
    private let blocking = Broadcast<BlockingScreen>()

    init(me: Result<MeResponse, AppError> = .success(.mock)) {
        meResult = me
    }

    var quotaUpdates: AsyncStream<Quota> { quota.stream }
    var blockingUpdates: AsyncStream<BlockingScreen> { blocking.stream }

    func health() async throws -> HealthResponse { .mock }

    func me() async throws -> MeResponse { try meResult.get() }
}

/// = `health.ok.response.json`.
extension HealthResponse {
    static let mock = HealthResponse(status: "ok", version: "0.1.0", schemaVersion: 1)
}

/// = `me.free.response.json`.
extension MeResponse {
    static let mock = MeResponse(
        schemaVersion: 1,
        userId: MockAuthService.userId,
        locale: "vi",
        plan: .free,
        quota: Quota(limit: 10, used: 3, remaining: 7, resetsAt: Date(timeIntervalSince1970: 1_794_157_200)), // 2026-11-09T00:00:00+07:00
        subscription: nil
    )
}

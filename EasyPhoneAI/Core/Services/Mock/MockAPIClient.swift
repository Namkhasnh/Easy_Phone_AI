import Foundation

/// In-memory `APIClientProtocol` for previews and tests (D-206). Never touches the network.
/// TODO(spec): switch to the shared contract fixtures in 0.18 (API_CONTRACT §10–§11).
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

extension HealthResponse {
    static let mock = HealthResponse(status: "ok", version: "0.1.0", schemaVersion: 1)
}

extension MeResponse {
    static let mock = MeResponse(
        schemaVersion: 1,
        userId: MockAuthService.userId,
        locale: "vi",
        plan: .free,
        quota: Quota(limit: 10, used: 3, remaining: 7, resetsAt: Date(timeIntervalSince1970: 1_762_621_200)),
        subscription: nil
    )
}

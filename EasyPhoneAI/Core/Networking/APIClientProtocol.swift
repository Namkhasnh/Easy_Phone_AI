import Foundation

/// All backend calls (ARCHITECTURE §4.1, API_CONTRACT §10). Live = `APIClient` actor, mock = `MockAPIClient` (D-206).
/// Throws `AppError` (or `CancellationError`). Methods for `/v1/extract`, `/v1/ocr`, `/v1/transcribe`,
/// `/v1/billing/verify`, `DELETE /v1/me` are added by the item that builds each endpoint.
protocol APIClientProtocol: Sendable {
    func health() async throws -> HealthResponse
    func me() async throws -> MeResponse
    /// `POST /v1/parse` (API_CONTRACT §7.1, 1 unit). `idempotencyKey`: one per endpoint call of a user action, made by
    /// the caller; the client reuses it for its own automatic retries only (D-230, D-245, ARCHITECTURE §10.1).
    func parse(_ request: ParseRequest, idempotencyKey: IdempotencyKey) async throws -> ParsedDraft
    /// From `X-Quota-*` headers after every response that carries them (D-234). Display only (D-085).
    var quotaUpdates: AsyncStream<Quota> { get }
    // TODO(spec): not in ARCHITECTURE §4.1 — lets any `426` reach `AppState.blockingScreen` (S19) without every
    // ViewModel catching it (UI_SCREENS §4 "Any API 426 ─▶ S19").
    var blockingUpdates: AsyncStream<BlockingScreen> { get }
}

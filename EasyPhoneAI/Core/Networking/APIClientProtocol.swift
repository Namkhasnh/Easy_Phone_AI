import Foundation

/// All backend calls (ARCHITECTURE §4.1, API_CONTRACT §10). Live = `APIClient` actor, mock = `MockAPIClient` (D-206).
/// Throws `AppError` (or `CancellationError`). Methods for
/// `/v1/billing/verify`, `DELETE /v1/me` are added by the item that builds each endpoint.
protocol APIClientProtocol: Sendable {
    func health() async throws -> HealthResponse
    func me() async throws -> MeResponse
    /// `POST /v1/parse` (API_CONTRACT §7.1, 1 unit). `idempotencyKey`: one per endpoint call of a user action, made by
    /// the caller; the client reuses it for its own automatic retries only (D-230, D-245, ARCHITECTURE §10.1).
    func parse(_ request: ParseRequest, idempotencyKey: IdempotencyKey) async throws -> ParsedDraft
    /// `POST /v1/transcribe` (API_CONTRACT §7.4): m4a ≤ 60 s / 2 MB, 0 units, rate-limited (429 → keyboard).
    /// The result is shown as editable text and never sent to `/v1/parse` by itself.
    func transcribe(m4a: Data, meta: MediaMeta) async throws -> TranscribeResponse
    /// `POST /v1/ocr` (API_CONTRACT §7.3, 1 unit, fallback only, D-061): JPEG ≤ 4 MB, long side ≤ 2048 px (the app's
    /// `ImageStore` copy already is). Own key per call (D-245); `/v1/extract` then uses a new one.
    func ocr(jpeg: Data, meta: MediaMeta, idempotencyKey: IdempotencyKey) async throws -> OCRResponse
    /// `POST /v1/extract` (API_CONTRACT §7.2, 1 unit): photo text → fields with UTF-16 spans. Own key (≠ the `/v1/ocr`
    /// one, D-245). Never called with empty text (spec §6.3 AC5).
    func extract(_ request: ExtractRequest, idempotencyKey: IdempotencyKey) async throws -> ExtractResponse
    /// From `X-Quota-*` headers after every response that carries them (D-234). Display only (D-085).
    var quotaUpdates: AsyncStream<Quota> { get }
    // TODO(spec): not in ARCHITECTURE §4.1 — lets any `426` reach `AppState.blockingScreen` (S19) without every
    // ViewModel catching it (UI_SCREENS §4 "Any API 426 ─▶ S19").
    var blockingUpdates: AsyncStream<BlockingScreen> { get }
}

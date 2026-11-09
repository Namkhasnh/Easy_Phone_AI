import Foundation

/// `GET /v1/health` (API_CONTRACT §6.1, D-235) = backend `schemas/health.py`.
struct HealthResponse: Codable, Sendable, Hashable {
    let status: String
    let version: String
    let schemaVersion: Int
}

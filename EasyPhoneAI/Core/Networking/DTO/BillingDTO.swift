import Foundation

/// `POST /v1/billing/verify` (API_CONTRACT §8.1, D-083). Response = `MeResponse` (§6.2).
struct BillingVerifyRequest: Codable, Sendable, Hashable {
    var schemaVersion = 1
    let signedTransaction: String
}

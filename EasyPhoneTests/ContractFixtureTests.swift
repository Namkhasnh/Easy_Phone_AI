import Foundation
import Testing
@testable import EasyPhoneAI

/// API_CONTRACT §11: the files in `backend/tests/fixtures/contract/` are bundled into this target
/// (synchronized folder in `project.xcproj`), so pytest and Swift test the same bytes.
@Suite("Contract fixtures (API_CONTRACT §11)")
struct ContractFixtureTests {
    /// The 13 codes of API_CONTRACT §3.2 (backend `schemas/error.py` `ErrorCode`).
    static let errorCodes = [
        "billing_invalid", "unauthorized", "quota_exceeded", "billing_account_mismatch", "not_found",
        "payload_too_large", "invalid_input", "client_outdated", "rate_limited", "internal",
        "llm_invalid_output", "upstream_error", "spend_cap",
    ]

    private static var bundle: Bundle { Bundle(for: BundleToken.self) }

    static var fixtureNames: [String] {
        (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".response.json") }
            .sorted()
    }

    static func data(_ name: String) throws -> Data {
        let url = try #require(bundle.url(forResource: name, withExtension: nil), "missing fixture \(name)")
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try APIClient.decoder().decode(type, from: data(name))
    }

    @Test func fixturesAreBundled() {
        #expect(Self.fixtureNames.count >= 3 + Self.errorCodes.count)
    }

    /// Decodes into the DTO and re-encodes without losing a key the fixture had (§11).
    @Test(arguments: fixtureNames)
    func decodesAndKeepsKeys(name: String) throws {
        let raw = try Self.data(name)
        let reencoded: Data
        switch name.split(separator: ".").first {
        case "health": reencoded = try JSONEncoder().encode(Self.decode(HealthResponse.self, name))
        case "me": reencoded = try JSONEncoder().encode(Self.decode(MeResponse.self, name))
        case "error": reencoded = try JSONEncoder().encode(Self.decode(APIErrorEnvelope.self, name))
        default:
            Issue.record("no DTO mapped for \(name)")
            return
        }
        let original = try Self.keyPaths(raw)
        let kept = try Self.keyPaths(reencoded)
        #expect(original.subtracting(kept).isEmpty, "lost keys: \(original.subtracting(kept))")
    }

    @Test(arguments: errorCodes)
    func everyErrorCodeHasAnEnvelope(code: String) throws {
        let envelope = try Self.decode(APIErrorEnvelope.self, "error.\(code).response.json")
        #expect(envelope.error.code == code)
        #expect(envelope.error.requestId?.hasPrefix("req_") == true)
        #expect(APIClient.apiError(try Self.data("error.\(code).response.json"), requestId: nil).code == code)
    }

    @Test func typedDetails() throws {
        let quota = try Self.decode(APIErrorEnvelope.self, "error.quota_exceeded.response.json").error.details
        #expect(quota?.plan == .free)
        #expect(quota?.quota?.remaining == 0)
        let outdated = try Self.decode(APIErrorEnvelope.self, "error.client_outdated.response.json").error.details
        #expect(outdated?.minVersion == "1.2.0")
        let rate = try Self.decode(APIErrorEnvelope.self, "error.rate_limited.response.json").error.details
        #expect(rate?.retryAfterSeconds == 120)
        let input = try Self.decode(APIErrorEnvelope.self, "error.invalid_input.response.json").error.details
        #expect(input?.field == "now")
        #expect(input?.reason == "missingOffset")
        let size = try Self.decode(APIErrorEnvelope.self, "error.payload_too_large.response.json").error.details
        #expect(size?.maxBytes == 4_194_304)
    }

    @Test func premiumSubscription() throws {
        let me = try Self.decode(MeResponse.self, "me.premium.response.json")
        #expect(me.plan == .premium)
        #expect(me.subscription?.status == .active)
        #expect(me.subscription?.environment == .sandbox)
    }

    /// Option A (owner 2026-11-09): mocks stay in code for previews, but must equal the fixtures byte-for-byte.
    @Test func mocksEqualFixtures() throws {
        #expect(MeResponse.mock == (try Self.decode(MeResponse.self, "me.free.response.json")))
        #expect(HealthResponse.mock == (try Self.decode(HealthResponse.self, "health.ok.response.json")))
    }

    /// Every key path (`quota.resetsAt`, `error.details.minVersion`) whose value is not null.
    static func keyPaths(_ data: Data) throws -> Set<String> {
        func walk(_ value: Any, _ prefix: String) -> Set<String> {
            guard let object = value as? [String: Any] else { return [] }
            var paths = Set<String>()
            for (key, child) in object where !(child is NSNull) {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                paths.insert(path)
                paths.formUnion(walk(child, path))
            }
            return paths
        }
        return walk(try JSONSerialization.jsonObject(with: data), "")
    }
}

private final class BundleToken {}

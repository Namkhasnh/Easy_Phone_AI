import Foundation
import Testing
@testable import EasyPhoneAI

@Suite("DTO decoding (API_CONTRACT §0, §3.1, §6.2)")
struct DTODecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(type, from: Data(json.utf8))
    }

    @Test func meIgnoresUnknownKeysAndKeepsOffsetDates() throws {
        let me = try decode(MeResponse.self, #"""
        {"schemaVersion":1,"userId":"6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11","locale":"vi","plan":"premium",
         "quota":{"limit":200,"used":0,"remaining":200,"resetsAt":"2026-11-09T00:00:00+07:00"},
         "subscription":{"productId":"easyphone.premium.monthly","status":"active",
                         "expiresAt":"2026-12-08T18:00:00+07:00","environment":"Sandbox"},
         "newServerField":true}
        """#)
        #expect(me.plan == .premium)
        #expect(me.quota.resetsAt == ISO8601DateFormatter().date(from: "2026-11-08T17:00:00Z"))
        #expect(me.subscription?.status == .active)
        #expect(me.subscription?.environment == .sandbox)
    }

    @Test func unknownEnumValuesDoNotCrash() throws {
        let me = try decode(MeResponse.self, #"""
        {"schemaVersion":1,"userId":"6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11","locale":"vi","plan":"family",
         "quota":{"limit":10,"used":0,"remaining":10,"resetsAt":"2026-11-09T00:00:00+07:00"},
         "subscription":{"productId":"x","status":"paused","expiresAt":null,"environment":"Moon"}}
        """#)
        #expect(me.plan == .free)
        #expect(me.subscription?.status == .unknown)
        #expect(me.subscription?.environment == .unknown)
    }

    @Test func missingRequiredKeyFails() {
        #expect(throws: DecodingError.self) {
            try decode(MeResponse.self, #"{"schemaVersion":1,"userId":"6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11"}"#)
        }
    }

    @Test func errorEnvelopeWithDetails() throws {
        let envelope = try decode(APIErrorEnvelope.self, #"""
        {"error":{"code":"quota_exceeded","message":"Bạn đã dùng hết lượt hôm nay.","retryable":false,
         "requestId":"req_01","details":{"plan":"free",
         "quota":{"limit":10,"used":10,"remaining":0,"resetsAt":"2026-11-09T00:00:00+07:00"}}}}
        """#)
        #expect(envelope.error.code == APIErrorCode.quotaExceeded)
        #expect(envelope.error.details?.plan == .free)
        #expect(envelope.error.details?.quota?.remaining == 0)
    }

    @Test func appErrorCodes() {
        #expect(AppError.network(.offline).code == "network.offline")
        #expect(AppError.api(code: "spend_cap", retryable: false, details: nil, requestId: nil).code == "spend_cap")
        #expect(AppError.service(.unavailable(AuthErrorCode.notSignedIn)).code == AuthErrorCode.notSignedIn)
        #expect(NetworkFailure(URLError(.timedOut)) == .timeout)
        #expect(NetworkFailure(URLError(.serverCertificateUntrusted)) == .tls)
        #expect(NetworkFailure(URLError(.cannotConnectToHost)) == .other)
    }
}

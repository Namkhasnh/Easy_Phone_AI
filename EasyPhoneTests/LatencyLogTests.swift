import Foundation
import Testing
@testable import EasyPhoneAI

/// D-319 — AI request timings (S15 Nâng cao).
@Suite("Latency log")
struct LatencyLogTests {
    @Test func parsesServerTiming() {
        let p = LatencyLog.parse("auth;dur=12.3, reserve;dur=80, llm;dur=1840.0, llm_repair;dur=100, total;dur=2100")
        #expect(p["auth"] == 12.3 && p["llm"] == 1840 && p["total"] == 2100)
        #expect(LatencyLog.parse("").isEmpty && LatencyLog.parse("bad, x;desc=y").isEmpty)
    }

    @Test func splitsAIServerNetwork() {
        let s = LatencySample(path: "/v1/parse", at: .now, totalMs: 2500,
                              server: ["llm": 1800, "llm_repair": 100, "reserve": 150, "total": 2100])
        #expect(s.aiMs == 1900 && s.serverOtherMs == 200 && s.networkMs == 400)
    }

    @Test func keepsOnlyAIPathsNewestFirstCapped() {
        let log = LatencyLog()
        log.record(path: "/v1/me", totalMs: 50, serverTiming: nil)
        for i in 0..<12 { log.record(path: "/v1/parse", totalMs: Double(i), serverTiming: "total;dur=1") }
        #expect(log.recent.count == LatencyLog.capacity && log.recent.first?.totalMs == 11)
        #expect(SettingsViewModel.seconds(2450) == "2,5" || SettingsViewModel.seconds(2450) == "2,4")
    }
}

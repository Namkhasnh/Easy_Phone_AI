import Foundation
import Synchronization

/// D-319: how long the AI requests took, split as the backend's `Server-Timing` reports it. Memory only (lost when
/// the app quits), names + milliseconds only (D-059). Shown in S15 Nâng cao → "Thời gian phản hồi".
struct LatencySample: Sendable, Hashable, Identifiable {
    let id = UUID()
    let path: String
    let at: Date
    /// Request sent → response headers received, on the phone.
    let totalMs: Double
    /// `Server-Timing` phases (`llm`, `reserve`, `auth`, …, `total`).
    let server: [String: Double]

    var aiMs: Double { server.filter { $0.key.hasPrefix("llm") }.values.reduce(0, +) }
    var serverOtherMs: Double { max(0, (server["total"] ?? 0) - aiMs) }
    var networkMs: Double { max(0, totalMs - (server["total"] ?? 0)) }
}

final class LatencyLog: Sendable {
    static let shared = LatencyLog()
    static let tracked: Set<String> = ["/v1/parse", "/v1/gmail/summary", "/v1/transcribe"]
    static let capacity = 10

    private let samples = Mutex<[LatencySample]>([])

    func record(path: String, totalMs: Double, serverTiming: String?, at: Date = .now) {
        guard Self.tracked.contains(path) else { return }
        let sample = LatencySample(path: path, at: at, totalMs: totalMs, server: Self.parse(serverTiming ?? ""))
        samples.withLock { list in
            list.insert(sample, at: 0)
            if list.count > Self.capacity { list.removeLast(list.count - Self.capacity) }
        }
    }

    /// Newest first.
    var recent: [LatencySample] { samples.withLock { $0 } }

    /// `auth;dur=12.3, llm;dur=1840.0, total;dur=1903.1` → `["auth": 12.3, "llm": 1840, "total": 1903.1]`.
    static func parse(_ header: String) -> [String: Double] {
        var out: [String: Double] = [:]
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = pieces.first, !name.isEmpty,
                  let dur = pieces.dropFirst().first(where: { $0.hasPrefix("dur=") }),
                  let value = Double(dur.dropFirst(4)) else { continue }
            out[name, default: 0] += value
        }
        return out
    }
}

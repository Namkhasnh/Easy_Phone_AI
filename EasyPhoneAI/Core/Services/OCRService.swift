import Foundation

/// ARCHITECTURE §4.3: `protocol OCRService { func recognize(_ image: ImageData) async throws -> OCRResult }`.
/// Images and text stay on the device unless the `/v1/ocr` fallback runs (ARCHITECTURE §9, D-056).
protocol OCRService: Sendable {
    func recognize(_ jpeg: Data) async throws -> OCRResult
}

/// Vision `NormalizedRect` space: 0–1, origin **bottom-left** (API_CONTRACT §7.3, same for both paths).
struct OCRBox: Codable, Sendable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct OCRLine: Codable, Sendable, Hashable {
    var text: String
    var box: OCRBox
    /// 0…1 from Vision; nil from `/v1/ocr`.
    var confidence: Double?
}

struct OCRResult: Sendable, Hashable {
    enum Source: String, Sendable, Hashable { case device, server }

    var lines: [OCRLine]
    var source: Source
    /// `lines[].text` joined by "\n" (API_CONTRACT §7.3).
    var text: String { lines.map(\.text).joined(separator: "\n") }
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Mean line confidence (P-24 / D-259); nil when no line has one.
    var meanConfidence: Double? {
        let values = lines.compactMap(\.confidence)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

/// The on-device recognizer used first by `RoutingOCRService`.
protocol DeviceOCR: Sendable {
    /// False when the OS has no Vietnamese text recognition → go straight to the fallback.
    func supportsVietnamese() async -> Bool
    func recognize(_ jpeg: Data) async throws -> OCRResult
}

/// `/v1/ocr` (API_CONTRACT §7.3, 1 unit). Wired to `APIClient.ocr` in 1D.4.
protocol RemoteOCR: Sendable {
    func recognize(_ jpeg: Data) async throws -> OCRResult
}

/// D-061 / D-259: Vision first; Vietnamese unsupported, nothing read, or mean confidence below the threshold →
/// `/v1/ocr`. If the fallback fails, a non-empty Vision result is still used; otherwise the error is thrown.
struct RoutingOCRService: OCRService {
    let device: any DeviceOCR
    let remote: any RemoteOCR
    /// `OCR_FALLBACK_MIN_CONFIDENCE` (P-24, D-259).
    // TODO(decision): D-060 is OPEN — the threshold is tuned with 10 real slips in 1D.10.
    var minConfidence: Double = 0.5

    func recognize(_ jpeg: Data) async throws -> OCRResult {
        var onDevice: OCRResult?
        if await device.supportsVietnamese() {
            let result = try? await device.recognize(jpeg)
            if let result, !result.isEmpty, (result.meanConfidence ?? 1) >= minConfidence { return result }
            onDevice = result
        }
        do {
            return try await remote.recognize(jpeg)
        } catch {
            // Weak text beats none (offline, no quota…); an empty result → S09 "no text" (1D.9), no extract call.
            if let onDevice { return onDevice }
            throw error
        }
    }
}

/// No fallback (previews / tests that must never spend a unit).
struct UnavailableRemoteOCR: RemoteOCR {
    func recognize(_ jpeg: Data) async throws -> OCRResult { throw ServiceError.unavailable("ocr.fallbackUnavailable") }
}

/// `RemoteOCR` = `POST /v1/ocr` (1 unit). A new key per call (D-245); `AppError`s (offline, 402…) pass through and
/// `RoutingOCRService` keeps the Vision result when it has one.
// TODO(spec): a 402 quota_exceeded here has no S09 text; the "no text" mode is shown when Vision read nothing.
struct APIRemoteOCR: RemoteOCR {
    let api: any APIClientProtocol

    func recognize(_ jpeg: Data) async throws -> OCRResult {
        let response = try await api.ocr(jpeg: jpeg, meta: .vietnamese, idempotencyKey: IdempotencyKey())
        return OCRResult(lines: response.lines.map { OCRLine(text: $0.text, box: $0.box, confidence: nil) }, source: .server)
    }
}

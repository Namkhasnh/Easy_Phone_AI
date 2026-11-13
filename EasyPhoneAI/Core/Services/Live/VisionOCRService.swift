import Foundation
import Vision

/// On-device text recognition (Vision `VNRecognizeTextRequest`, accurate, Vietnamese first). Never leaves the phone.
final class VisionOCRService: DeviceOCR {
    static let languages = ["vi-VN", "en-US"]

    func supportsVietnamese() async -> Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        return supported.contains { $0.lowercased().hasPrefix("vi") }
    }

    func recognize(_ jpeg: Data) async throws -> OCRResult {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = Self.languages
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(data: jpeg, options: [:])   // EXIF orientation is applied
            do {
                try handler.perform([request])
            } catch {
                throw ServiceError.framework(code: "ocr.failed")
            }
            let observations = request.results ?? []
            // Reading order: top to bottom (origin bottom-left → larger y first), then left to right.
            let lines = observations.compactMap { obs -> OCRLine? in
                guard let best = obs.topCandidates(1).first else { return nil }
                let r = obs.boundingBox
                return OCRLine(text: best.string,
                               box: OCRBox(x: r.minX, y: r.minY, width: r.width, height: r.height),
                               confidence: Double(best.confidence))
            }.sorted { a, b in
                abs(a.box.y - b.box.y) > 0.01 ? a.box.y > b.box.y : a.box.x < b.box.x
            }
            return OCRResult(lines: lines, source: .device)
        }.value
    }
}

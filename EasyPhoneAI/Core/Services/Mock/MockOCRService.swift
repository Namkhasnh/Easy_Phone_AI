import Foundation
import Synchronization

/// Fixed `OCRService` / `DeviceOCR` / `RemoteOCR` answers for previews and tests (D-206).
final class MockOCRService: OCRService, DeviceOCR, RemoteOCR {
    private let state: Mutex<(result: Result<OCRResult, ServiceError>, vi: Bool, calls: Int)>

    init(_ result: Result<OCRResult, ServiceError> = .success(.sample), supportsVietnamese: Bool = true) {
        state = Mutex((result, supportsVietnamese, 0))
    }

    var calls: Int { state.withLock { $0.calls } }

    func supportsVietnamese() async -> Bool { state.withLock { $0.vi } }

    func recognize(_ jpeg: Data) async throws -> OCRResult {
        try state.withLock { s in
            s.calls += 1
            return try s.result.get()
        }
    }
}

extension OCRResult {
    /// "Dữ liệu mẫu" appointment slip (D-189), like the API_CONTRACT §7.3 example.
    static let sample = OCRResult(lines: [
        OCRLine(text: "PHÒNG KHÁM NHA KHOA AN BÌNH", box: OCRBox(x: 0.08, y: 0.86, width: 0.84, height: 0.05), confidence: 0.9),
        OCRLine(text: "Lịch hẹn: 09:30 ngày 14/11/2026", box: OCRBox(x: 0.08, y: 0.78, width: 0.70, height: 0.04), confidence: 0.85),
    ], source: .device)
}

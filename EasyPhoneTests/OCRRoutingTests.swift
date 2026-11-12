import Foundation
import Testing
@testable import EasyPhoneAI

/// 1D.3 — ARCHITECTURE §4.3 / §6.4, D-061, D-259 (threshold 0.5), spec §6.3 AC5.
@MainActor
@Suite("RoutingOCRService + S09 reading")
struct OCRRoutingTests {
    nonisolated static func result(_ lines: [(String, Double?)], _ source: OCRResult.Source = .device) -> OCRResult {
        OCRResult(lines: lines.map { OCRLine(text: $0.0, box: OCRBox(x: 0, y: 0, width: 1, height: 0.1), confidence: $0.1) },
                  source: source)
    }
    nonisolated static let good = result([("Lịch hẹn 09:30", 0.9), ("Nha khoa An Bình", 0.8)])
    nonisolated static let weak = result([("L1ch h3n", 0.3)])
    nonisolated static let server = result([("Lịch hẹn: 09:30 ngày 14/11/2026", nil)], .server)
    nonisolated static let empty = result([])

    @Test func goodVisionTextNeverCallsTheServer() async throws {
        let remote = MockOCRService(.success(Self.server))
        let out = try await RoutingOCRService(device: MockOCRService(.success(Self.good)), remote: remote).recognize(Data())
        #expect(out.source == .device && out.text == "Lịch hẹn 09:30\nNha khoa An Bình")
        #expect(remote.calls == 0)                                              // no unit spent
    }

    @Test(arguments: [weak, empty])
    func weakOrEmptyVisionFallsBack(device: OCRResult) async throws {
        let remote = MockOCRService(.success(Self.server))
        let out = try await RoutingOCRService(device: MockOCRService(.success(device)), remote: remote).recognize(Data())
        #expect(out.source == .server && remote.calls == 1)
    }

    @Test func noVietnameseGoesStraightToTheServer() async throws {
        let device = MockOCRService(.success(Self.good), supportsVietnamese: false)
        let out = try await RoutingOCRService(device: device, remote: MockOCRService(.success(Self.server))).recognize(Data())
        #expect(out.source == .server && device.calls == 0)
    }

    @Test func fallbackFailsKeepsWeakVisionText() async throws {
        let out = try await RoutingOCRService(device: MockOCRService(.success(Self.weak)),
                                              remote: UnavailableRemoteOCR()).recognize(Data())
        #expect(out.text == "L1ch h3n")
    }

    @Test func nothingAnywhereThrows() async {
        let routing = RoutingOCRService(device: MockOCRService(.success(Self.good), supportsVietnamese: false),
                                        remote: UnavailableRemoteOCR())
        await #expect(throws: ServiceError.self) { try await routing.recognize(Data()) }
    }

    @Test func meanConfidenceAndText() {
        #expect(Self.good.meanConfidence! > 0.84 && Self.server.meanConfidence == nil && Self.empty.isEmpty)
    }

    // MARK: - S09

    func model(_ ocr: MockOCRService, repo: MockTaskRepository) -> OCRCaptureViewModel {
        OCRCaptureViewModel(permissions: MockPermissionManager(), cameraAvailable: false, repository: repo, ocr: ocr)
    }

    @Test func textFoundIsSavedAsOriginalInput() async throws {
        let repo = MockTaskRepository()
        let vm = model(MockOCRService(.success(Self.good)), repo: repo)
        await vm.received(Data([1]), fromCamera: false)
        #expect(vm.mode == .read && vm.readText == "Lịch hẹn 09:30\nNha khoa An Bình")
        #expect(repo.draft(try #require(vm.draftId))?.originalInput == vm.readText)   // D-104
    }

    @Test func noTextShowsRetake() async throws {
        let repo = MockTaskRepository()
        let vm = model(MockOCRService(.success(Self.empty)), repo: repo)
        await vm.received(Data([1]), fromCamera: false)
        #expect(vm.mode == .noText)
        #expect(repo.draft(try #require(vm.draftId))?.originalInput == "")
    }

    @Test func readErrorShowsRetake() async {
        let vm = model(MockOCRService(.failure(.framework(code: "ocr.failed"))), repo: MockTaskRepository())
        await vm.received(Data([1]), fromCamera: false)
        #expect(vm.mode == .noText)
    }
}

/// 1D.4 — `APIRemoteOCR` = `/v1/ocr` (own key per call, D-245), boxes kept for S10.
@MainActor
@Suite("APIRemoteOCR")
struct APIRemoteOCRTests {
    @Test func callsOcrWithTheJpegAndANewKeyEachTime() async throws {
        let api = MockAPIClient()
        let remote = APIRemoteOCR(api: api)
        let out = try await remote.recognize(Data([0xFF, 0xD8]))
        #expect(out.source == .server && out.text == OCRResponse.mock.text)
        #expect(out.lines.first?.box == OCRBox(x: 0.08, y: 0.86, width: 0.84, height: 0.05))
        _ = try await remote.recognize(Data([0xFF, 0xD8]))
        #expect(api.ocrCalls.count == 2 && api.ocrCalls[0].jpeg == Data([0xFF, 0xD8]))
        #expect(api.ocrCalls[0].key != api.ocrCalls[1].key)
    }

    @Test func weakVisionPlusServerUsesTheServerText() async throws {
        let api = MockAPIClient()
        let routing = RoutingOCRService(device: MockOCRService(.success(OCRRoutingTests.weak)), remote: APIRemoteOCR(api: api))
        let out = try await routing.recognize(Data([1]))
        #expect(out.source == .server && api.ocrCalls.count == 1)
    }

    @Test func offlineServerKeepsWeakVisionText() async throws {
        let api = MockAPIClient(ocr: .failure(.network(.offline)))
        let routing = RoutingOCRService(device: MockOCRService(.success(OCRRoutingTests.weak)), remote: APIRemoteOCR(api: api))
        #expect(try await routing.recognize(Data([1])).text == "L1ch h3n")
    }
}

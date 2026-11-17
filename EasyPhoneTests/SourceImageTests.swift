import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import EasyPhoneAI

/// 1D.8 — S10 Source image: span → OCR line boxes (DATA_MODEL §1.7, D-126), caption / VoiceOver text, highlight
/// rectangle in SwiftUI space, image loaded from the 🔒 ImageStore, opened from S04 "Xem ảnh gốc".
@MainActor
@Suite("S10 source image")
struct SourceImageTests {
    let sample = OCRResult.sample
    var text: String { sample.text }

    @Test func spanInOneLineGetsThatLinesBox() {
        let title = DraftBuilder.box(0, 27, text: text, lines: sample.lines)
        #expect(title == NormalizedRect(x: 0.08, y: 0.86, width: 0.84, height: 0.05))
        let date = DraftBuilder.box(38, 59, text: text, lines: sample.lines)
        #expect(date == NormalizedRect(x: 0.08, y: 0.78, width: 0.70, height: 0.04))
    }

    @Test func spanOverTwoLinesGetsTheUnion() throws {
        let box = try #require(DraftBuilder.box(20, 40, text: text, lines: sample.lines))
        #expect(abs(box.x - 0.08) < 1e-9 && abs(box.y - 0.78) < 1e-9)
        #expect(abs(box.width - 0.84) < 1e-9 && abs(box.height - 0.13) < 1e-9)
    }

    @Test func noBoxWhenTextDoesNotMatchTheLinesOrSpanIsOutside() {
        #expect(DraftBuilder.box(0, 5, text: "khác", lines: sample.lines) == nil)
        #expect(DraftBuilder.box(0, 5, text: text, lines: []) == nil)
        #expect(DraftBuilder.box(27, 28, text: text, lines: sample.lines) == nil)   // only the "\n"
    }

    @Test func ocrStepStoresBoxesWithTheSpans() {
        let step = DraftBuilder.ocrStep(text: text, extract: .mock, lines: sample.lines, now: .now)
        guard case .ocr(let span) = step.field("dateTime")?.source else { Issue.record("no span"); return }
        #expect(span.boundingBox == NormalizedRect(x: 0.08, y: 0.78, width: 0.70, height: 0.04))
    }

    @Test func highlightFlipsToTopLeft() throws {
        let vm = SourceImageViewModel(imagePath: nil, images: MockImageStore(),
                                      box: NormalizedRect(x: 0.1, y: 0.7, width: 0.5, height: 0.1),
                                      fieldLabel: "Ngày giờ", spanText: nil)
        let rect = try #require(vm.highlight(in: CGSize(width: 200, height: 400)))
        #expect(abs(rect.minX - 20) < 1e-9 && abs(rect.minY - 80) < 1e-9)
        #expect(abs(rect.width - 100) < 1e-9 && abs(rect.height - 40) < 1e-9)
    }

    @Test func captionNeedsImageAndBox() async throws {
        let store = MockImageStore()
        let path = try await store.save(Self.jpeg(), draftId: UUID())
        let vm = SourceImageViewModel(imagePath: path, images: store,
                                      box: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                                      fieldLabel: "Ngày giờ", spanText: "09:30 ngày 14/11/2026")
        #expect(vm.caption == UserMessage(key: "source.noBox").text)          // not loaded yet
        await vm.load()
        #expect(vm.image?.width == 8 && vm.didLoad)
        #expect(vm.caption == UserMessage(key: "source.caption", args: ["Ngày giờ"]).text)
        #expect(vm.accessibilityText.hasSuffix("09:30 ngày 14/11/2026"))

        let missing = SourceImageViewModel(imagePath: "ocr/none.jpg", images: store, box: nil,
                                           fieldLabel: "Ngày giờ", spanText: nil)
        await missing.load()
        #expect(missing.image == nil && missing.didLoad && missing.caption == UserMessage(key: "source.noBox").text)
    }

    @Test func reviewOpensS10OnlyForOCRFields() {
        let repo = MockTaskRepository()
        let engine = TaskEngine(repository: repo)
        let draft = TaskDraft(inputMode: .photo, originalInput: text)
        draft.imageLocalPath = "ocr/x.jpg"
        repo.save(draft)
        engine.applyExtract(.mock, text: text, lines: sample.lines, to: draft)
        let vm = ReviewViewModel(draftId: draft.id, repository: repo, engine: engine,
                                 permissions: MockPermissionManager())
        vm.viewSource(draft.steps[0].field("extractedText")!)                // `.device("ocr")`, no span
        #expect(vm.sourceImage == nil)
        vm.viewSource(draft.steps[0].field("title")!)
        #expect(vm.sourceImage?.spanText == "PHÒNG KHÁM NHA KHOA AN BÌNH")
        #expect(vm.sourceImage?.fieldLabel == UserMessage(key: "field.ocr.title").text)
        #expect(vm.sourceImage?.box == NormalizedRect(x: 0.08, y: 0.86, width: 0.84, height: 0.05))
    }

    /// A tiny 8×4 JPEG made with ImageIO.
    static func jpeg() -> Data {
        let ctx = CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }
}

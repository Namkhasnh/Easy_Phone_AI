import CoreGraphics
import Foundation
import ImageIO
import Observation

/// S10 Source image (UI_SCREENS S10, D-126): the photo of an `ocr` draft with the region one field was read from.
/// The image stays on the phone (🔒 `imageLocalPath`, D-056). No business rules; nothing is written.
@Observable @MainActor final class SourceImageViewModel {
    /// The decoded photo (ImageStore already applied the EXIF orientation, ARCHITECTURE §6.4); nil until loaded / missing.
    private(set) var image: CGImage?
    private(set) var didLoad = false
    /// 0–1, origin bottom-left (Vision space, DATA_MODEL §1.7).
    let box: NormalizedRect?
    /// The field's label, e.g. "Ngày giờ".
    let fieldLabel: String
    /// The OCR text the span covers (read by VoiceOver with the caption, UI_SCREENS S10).
    let spanText: String?

    private let imagePath: String?
    private let images: any ImageStore

    init(imagePath: String?, images: any ImageStore, box: NormalizedRect?, fieldLabel: String, spanText: String?) {
        self.imagePath = imagePath
        self.images = images
        self.box = box
        self.fieldLabel = fieldLabel
        self.spanText = spanText
    }

    /// For one OCR field of `draft`: label from `field.<kind>.<id>`, box + text from its span.
    convenience init(field: Field, kind: TaskKind, draft: TaskDraft, images: any ImageStore) {
        var box: NormalizedRect?
        var text: String?
        if case .ocr(let span) = field.source {
            box = span.boundingBox
            let utf16 = Array(draft.originalInput.utf16)
            if span.start >= 0, span.end <= utf16.count, span.start < span.end {
                text = String(decoding: utf16[span.start..<span.end], as: UTF16.self)
            }
        }
        self.init(imagePath: draft.imageLocalPath, images: images, box: box,
                  fieldLabel: String(localized: String.LocalizationValue(field.labelKey(kind: kind))), spanText: text)
    }

    /// `source.caption` when the region is known, else `source.noBox`.
    var caption: String {
        guard box != nil, image != nil else { return UserMessage(key: "source.noBox").text }
        return UserMessage(key: "source.caption", args: [fieldLabel]).text
    }

    /// VoiceOver: caption + span text (UI_SCREENS S10).
    var accessibilityText: String {
        [caption, spanText].compactMap { $0 }.joined(separator: ". ")
    }

    func load() async {
        defer { didLoad = true }
        guard image == nil, let imagePath, let data = await images.load(imagePath),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The box in a top-left space of `size` (SwiftUI), or nil.
    func highlight(in size: CGSize) -> CGRect? {
        guard let box else { return nil }
        return CGRect(x: box.x * size.width, y: (1 - box.y - box.height) * size.height,
                      width: box.width * size.width, height: box.height * size.height)
    }
}

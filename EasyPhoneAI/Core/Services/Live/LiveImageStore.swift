import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO downscale (≤ 2048 px, orientation applied) + JPEG, written atomically, excluded from backup.
final class LiveImageStore: ImageStore {
    private let base: URL

    init(base: URL? = nil) {
        self.base = base ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    func save(_ data: Data, draftId: UUID) async throws -> String {
        let jpeg = try Self.downscaledJPEG(data)
        let relative = ImageStoreLimits.path(for: draftId)
        var url = base.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true                       // private documents, D-056
        try? url.setResourceValues(values)
        return relative
    }

    func load(_ relativePath: String) async -> Data? { try? Data(contentsOf: base.appending(path: relativePath)) }

    func delete(_ relativePath: String) async { try? FileManager.default.removeItem(at: base.appending(path: relativePath)) }

    static func downscaledJPEG(_ data: Data, maxPixelSize: Int = ImageStoreLimits.maxPixelSize) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary) else { throw ServiceError.framework(code: "ocr.imageUnreadable") }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ServiceError.framework(code: "ocr.imageUnreadable")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ServiceError.framework(code: "ocr.imageUnreadable") }
        return out as Data
    }
}

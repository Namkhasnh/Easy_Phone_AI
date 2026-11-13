import Foundation

/// ARCHITECTURE §6.4: the OCR photo as JPEG in `Application Support/ocr/<draftId>.jpg` (🔒 never sent as a path,
/// D-056). Longest side ≤ 2048 px (the same file is the `/v1/ocr` fallback upload, API_CONTRACT).
protocol ImageStore: Sendable {
    /// Saves `data` (any image format) for `draftId`; returns the relative path stored in `TaskDraft.imageLocalPath`.
    func save(_ data: Data, draftId: UUID) async throws -> String
    func load(_ relativePath: String) async -> Data?
    func delete(_ relativePath: String) async
}

/// D-301: camera photos may also be added to the iPhone Photos library (add-only access, default off).
protocol PhotoLibraryService: Sendable {
    /// Asks for add-only access when never asked; true when the app may add photos.
    func requestAddAccess() async -> Bool
    func add(_ jpeg: Data) async throws
}

enum ImageStoreLimits {
    static let maxPixelSize = 2048
    static func path(for draftId: UUID) -> String { "ocr/\(draftId.uuidString).jpg" }
}

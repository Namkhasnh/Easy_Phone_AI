import Foundation
import Synchronization

/// In-memory `ImageStore` / `PhotoLibraryService` for previews and tests (D-206).
final class MockImageStore: ImageStore {
    private let files = Mutex<[String: Data]>([:])
    var stored: [String: Data] { files.withLock { $0 } }

    func save(_ data: Data, draftId: UUID) async throws -> String {
        let path = ImageStoreLimits.path(for: draftId)
        files.withLock { $0[path] = data }
        return path
    }

    func load(_ relativePath: String) async -> Data? { files.withLock { $0[relativePath] } }
    func delete(_ relativePath: String) async { _ = files.withLock { $0.removeValue(forKey: relativePath) } }
}

final class MockPhotoLibraryService: PhotoLibraryService {
    private let state: Mutex<(allowed: Bool, added: [Data])>
    init(allowed: Bool = true) { state = Mutex((allowed, [])) }
    var added: [Data] { state.withLock { $0.added } }

    func requestAddAccess() async -> Bool { state.withLock { $0.allowed } }
    func add(_ jpeg: Data) async throws {
        try state.withLock { s in
            guard s.allowed else { throw ServiceError.permissionDenied(.photos) }
            s.added.append(jpeg)
        }
    }
}

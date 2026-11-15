import Photos

/// D-301: add-only Photos access; the app never reads the library (PhotosPicker runs out of process).
final class LivePhotoLibraryService: PhotoLibraryService {
    func requestAddAccess() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited
        default: return false
        }
    }

    func add(_ jpeg: Data) async throws {
        guard await requestAddAccess() else { throw ServiceError.permissionDenied(.photos) }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpeg, options: nil)
        }
    }
}

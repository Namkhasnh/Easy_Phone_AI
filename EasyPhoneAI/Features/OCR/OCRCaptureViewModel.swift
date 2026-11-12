import Foundation
import Observation
import OSLog

/// S09 step 1 "Choose source" (UI_SCREENS S09): camera (S18 step 0, D-185) or one photo from the library
/// (`PhotosPicker` runs out of process, no Photos access needed). Reading (1D.3) and saving (1D.2) come next.
@Observable @MainActor final class OCRCaptureViewModel {
    enum Mode: Equatable { case choosing, captured }

    private(set) var mode: Mode = .choosing
    /// JPEG of the chosen photo (🔒 stays on the device, D-056).
    private(set) var imageData: Data?
    var showsCamera = false
    var showsLibrary = false
    var pendingPermission: PendingPermission?

    /// The new `.photo` draft holding the saved image (1D.2); the OCR step is added by 1D.3 / 1D.7.
    private(set) var draftId: UUID?
    /// Saving the photo failed (unreadable / disk): S09 asks for another photo.
    private(set) var saveFailed = false

    let cameraAvailable: Bool
    private let permissions: any PermissionManager
    private let repository: any TaskRepository
    private let images: any ImageStore
    private let photoLibrary: any PhotoLibraryService
    private let localData: any LocalDataRepository
    private let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "ocrCapture")

    init(permissions: any PermissionManager, cameraAvailable: Bool, repository: any TaskRepository = MockTaskRepository(),
         images: any ImageStore = MockImageStore(), photoLibrary: any PhotoLibraryService = MockPhotoLibraryService(),
         localData: any LocalDataRepository = MockLocalDataRepository()) {
        self.permissions = permissions
        self.cameraAvailable = cameraAvailable
        self.repository = repository
        self.images = images
        self.photoLibrary = photoLibrary
        self.localData = localData
    }

    /// "Chụp ảnh": never asked → S18 explainer; denied → S18 denied with "Chọn ảnh có sẵn" as fallback.
    func chooseCamera() {
        switch permissions.status(.camera) {
        case .notDetermined: pendingPermission = PendingPermission(capability: .camera, variant: .explainer)
        case .denied, .restricted: pendingPermission = PendingPermission(capability: .camera, variant: .denied)
        case .granted, .limited, .writeOnly: showsCamera = true
        }
    }

    func chooseLibrary() { showsLibrary = true }

    /// S18 "Cho phép" → system alert → camera, or the denied variant.
    func allowPermission() async {
        guard pendingPermission?.variant == .explainer else { return }
        pendingPermission = nil
        let status = await permissions.request(.camera)
        if status.isUsable {
            showsCamera = true
        } else {
            pendingPermission = PendingPermission(capability: .camera, variant: .denied)
        }
    }

    /// S18 denied fallback `perm.camera.fallback` = "Chọn ảnh có sẵn".
    func useLibraryInstead() {
        pendingPermission = nil
        showsLibrary = true
    }

    func dismissPermission() { pendingPermission = nil }

    /// A photo from the camera or the library (exactly one, `ocr.oneImageNote`): a new `.photo` draft, the JPEG saved
    /// in the app (≤ 2048 px, D-056) and its path stored (autosave, D-104). Camera photos are also added to Photos
    /// when `settings.savePhotos` is on (D-301); a failure there never blocks reading.
    // TODO(spec): 1D.3 reads the saved image (mode "Reading").
    func received(_ data: Data, fromCamera: Bool) async {
        showsCamera = false
        showsLibrary = false
        saveFailed = false
        let draft = TaskDraft(inputMode: .photo, originalInput: "")
        do {
            draft.imageLocalPath = try await images.save(data, draftId: draft.id)
        } catch {
            logger.info("photo not saved: \((error as? ServiceError)?.code ?? "unknown", privacy: .public)")
            saveFailed = true
            return
        }
        repository.save(draft)
        draftId = draft.id
        imageData = data
        mode = .captured
        if fromCamera, localData.settings().savePhotos {
            do { try await photoLibrary.add(data) } catch { logger.info("photo not added to Photos") }
        }
    }

    /// "Chụp lại" / "Chọn ảnh khác": the unread photo and its empty draft are removed; back to choosing.
    func retake() async {
        if let draftId, let draft = repository.draft(draftId), draft.steps.isEmpty, let path = draft.imageLocalPath {
            await images.delete(path)
            draft.imageLocalPath = nil
            repository.save(draft)
            // TODO(spec): TaskRepository has no delete for one draft; the empty draft stays (no row: no steps).
        }
        draftId = nil
        imageData = nil
        mode = .choosing
    }
}

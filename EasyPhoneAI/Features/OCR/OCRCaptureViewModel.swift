import Foundation
import Observation

/// S09 step 1 "Choose source" (UI_SCREENS S09): camera (S18 step 0, D-185) or one photo from the library
/// (`PhotosPicker` runs out of process, no Photos access needed). Reading (1D.3) and saving (1D.2) come next.
@Observable @MainActor final class OCRCaptureViewModel {
    enum Mode: Equatable { case choosing, captured }

    private(set) var mode: Mode = .choosing
    /// JPEG of the chosen photo (🔒 stays on the device, D-056).
    private(set) var imageData: Data?
    /// The source dialog ("Chụp ảnh" / "Chọn ảnh có sẵn" / "Hủy").
    var showsSourceDialog = true
    var showsCamera = false
    var showsLibrary = false
    var pendingPermission: PendingPermission?

    let cameraAvailable: Bool
    private let permissions: any PermissionManager

    init(permissions: any PermissionManager, cameraAvailable: Bool) {
        self.permissions = permissions
        self.cameraAvailable = cameraAvailable
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

    /// A photo from the camera or the library (exactly one, `ocr.oneImageNote`).
    // TODO(spec): 1D.2 saves it to `Application Support/ocr/<draftId>.jpg`, 1D.3 reads it (mode "Reading").
    func received(_ data: Data) {
        imageData = data
        mode = .captured
        showsCamera = false
        showsLibrary = false
    }

    /// "Chụp lại" / "Chọn ảnh khác": back to the source dialog; the old photo is dropped.
    func retake() {
        imageData = nil
        mode = .choosing
        showsSourceDialog = true
    }
}

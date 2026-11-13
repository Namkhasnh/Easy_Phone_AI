import Foundation
import Observation
import OSLog

/// S09 step 1 "Choose source" (UI_SCREENS S09): camera (S18 step 0, D-185) or one photo from the library
/// (`PhotosPicker` runs out of process, no Photos access needed). Reading (1D.3) and saving (1D.2) come next.
@Observable @MainActor final class OCRCaptureViewModel {
    /// S09 modes: 1 choose source, 2 reading, 3 text found (fields come with 1D.7), 4 no text / blurry (spec §6.3 AC5).
    enum Mode: Equatable { case choosing, reading, read, noText }

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
    /// What was read (lines + boxes for S10 "Xem ảnh gốc", 1D.8). Text only, never sent from here.
    private(set) var result: OCRResult?
    /// Set when the `ocr` step is ready → the view replaces S09 with S04 (UI_SCREENS S09 step 3).
    private(set) var reviewDraftId: UUID?

    let cameraAvailable: Bool
    private let permissions: any PermissionManager
    private let repository: any TaskRepository
    private let images: any ImageStore
    private let photoLibrary: any PhotoLibraryService
    private let localData: any LocalDataRepository
    private let ocr: any OCRService
    private let api: any APIClientProtocol
    private let engine: TaskEngine
    private let now: @MainActor () -> Date
    private let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "ocrCapture")

    init(permissions: any PermissionManager, cameraAvailable: Bool, repository: any TaskRepository = MockTaskRepository(),
         images: any ImageStore = MockImageStore(), photoLibrary: any PhotoLibraryService = MockPhotoLibraryService(),
         localData: any LocalDataRepository = MockLocalDataRepository(), ocr: any OCRService = MockOCRService(),
         api: any APIClientProtocol = MockAPIClient(), engine: TaskEngine? = nil,
         now: @escaping @MainActor () -> Date = { .now }) {
        self.ocr = ocr
        self.api = api
        self.engine = engine ?? TaskEngine(repository: repository)
        self.now = now
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
        mode = .reading
        if fromCamera, localData.settings().savePhotos {
            do { try await photoLibrary.add(data) } catch { logger.info("photo not added to Photos") }
        }
        await read(draft)
    }

    /// Mode 2 → 3 / 4. The text becomes `originalInput` (DATA_MODEL §3.2) and is saved at once (D-104), then
    /// `/v1/extract` (1 unit, own key) turns it into fields and the `ocr` step opens in S04.
    private func read(_ draft: TaskDraft) async {
        guard let path = draft.imageLocalPath, let jpeg = await images.load(path) else { mode = .noText; return }
        do {
            let result = try await ocr.recognize(jpeg)
            self.result = result
            guard !result.isEmpty else { mode = .noText; return }        // spec §6.3 AC5: no `/v1/extract` call
            draft.originalInput = result.text
            repository.save(draft)
            await extract(result.text, draft: draft)
            mode = .read
        } catch {
            // TODO(spec): S09 has no text for a failed read (offline fallback…); the "no text" mode offers a retake.
            logger.info("ocr failed: \((error as? ServiceError)?.code ?? "unknown", privacy: .public)")
            mode = .noText
        }
    }

    /// API_CONTRACT §7.2. The text is sent as data only (the backend wraps it, D-057); no image, no 🔒 value (D-056).
    /// Any failure (offline, quota, 5xx) still opens S04 with the text, so nothing read is lost (D-104).
    // TODO(spec): S09 has no message for a failed `/v1/extract` (offline, 402 quota…); S04 opens with `extractedText`
    // only and the user fills the rest by hand. Revisit with 1F (paywall on 402).
    private func extract(_ text: String, draft: TaskDraft) async {
        let zone = TimeZone(identifier: draft.timeZoneId) ?? .current
        let request = ExtractRequest(ocrText: text, now: ParseRequest.nowString(now(), in: zone),
                                     timezone: zone.identifier, locale: draft.locale)
        var response: ExtractResponse?
        do {
            response = try await api.extract(request, idempotencyKey: IdempotencyKey())  // one key per call (D-245)
        } catch {
            logger.info("extract failed: \((error as? AppError)?.code ?? "unknown", privacy: .public)")
        }
        if engine.applyExtract(response, text: text, to: draft) || !draft.steps.isEmpty {
            reviewDraftId = draft.id
        }
    }

    /// Mode 3 text, one line per row (data from the photo, shown as is).
    var readText: String { result?.text ?? "" }

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
        result = nil
        mode = .choosing
    }
}

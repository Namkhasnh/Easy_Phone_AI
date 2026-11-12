import Foundation
import Testing
import UIKit
@testable import EasyPhoneAI

/// 1D.2 — ARCHITECTURE §6.4 (JPEG ≤ 2048 px in `Application Support/ocr/<draftId>.jpg` 🔒), D-104, D-301.
@MainActor
@Suite("OCR photo storage + save to Photos")
struct OCRImageStoreTests {
    let repo = MockTaskRepository()
    let images = MockImageStore()
    let library = MockPhotoLibraryService()
    let local = MockLocalDataRepository()

    func model() -> OCRCaptureViewModel {
        OCRCaptureViewModel(permissions: MockPermissionManager([.camera: .granted]), cameraAvailable: true,
                            repository: repo, images: images, photoLibrary: library, localData: local)
    }

    static let photo = Data([0xFF, 0xD8, 0x01])

    @Test func photoCreatesAPhotoDraftWithTheSavedPath() async throws {
        let vm = model()
        await vm.received(Self.photo, fromCamera: false)
        let id = try #require(vm.draftId)
        let draft = try #require(repo.draft(id))
        #expect(draft.inputMode == .photo && draft.steps.isEmpty)
        #expect(draft.imageLocalPath == "ocr/\(id.uuidString).jpg")                 // relative, device only
        #expect(images.stored[draft.imageLocalPath!] == Self.photo)
        #expect(vm.mode == .captured)
    }

    @Test func retakeDeletesTheUnreadPhoto() async throws {
        let vm = model()
        await vm.received(Self.photo, fromCamera: true)
        let path = try #require(repo.draft(vm.draftId!)?.imageLocalPath)
        await vm.retake()
        #expect(images.stored[path] == nil && vm.draftId == nil && vm.mode == .choosing)
    }

    @Test func savePhotosOffNeverTouchesPhotos() async {
        await model().received(Self.photo, fromCamera: true)                      // default off (D-301)
        #expect(library.added.isEmpty)
    }

    @Test func savePhotosOnAddsCameraPhotosOnly() async {
        local.settings().savePhotos = true
        let vm = model()
        await vm.received(Self.photo, fromCamera: false)                          // from the library: no duplicate
        #expect(library.added.isEmpty)
        await vm.received(Self.photo, fromCamera: true)
        #expect(library.added == [Self.photo])
    }

    @Test func settingsToggleRevertsWhenRefused() async {
        let vm = SettingsViewModel(localData: local, drafts: repo, auth: MockAuthService(),
                                   photoLibrary: MockPhotoLibraryService(allowed: false))
        #expect(vm.settings.savePhotos == false)
        vm.settings.savePhotos = true
        await vm.savePhotosChanged()
        #expect(vm.settings.savePhotos == false)
        let ok = SettingsViewModel(localData: local, drafts: repo, auth: MockAuthService(), photoLibrary: library)
        ok.settings.savePhotos = true
        await ok.savePhotosChanged()
        #expect(ok.settings.savePhotos)
    }

    @Test func liveDownscaleKeepsTheLongSideAt2048() throws {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000),
                                          format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .jpegData(withCompressionQuality: 0.8) { ctx in UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000)) }
        let out = try LiveImageStore.downscaledJPEG(big)
        let image = try #require(UIImage(data: out))
        #expect(max(image.size.width * image.scale, image.size.height * image.scale) == 2048)
        #expect(throws: ServiceError.self) { try LiveImageStore.downscaledJPEG(Data("not an image".utf8)) }
    }

    @Test func liveStoreWritesUnderOcrAndDeletes() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = LiveImageStore(base: dir)
        let png = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).pngData { _ in }
        let id = UUID()
        let path = try await store.save(png, draftId: id)
        #expect(path == "ocr/\(id.uuidString).jpg")
        #expect(await store.load(path) != nil)
        await store.delete(path)
        #expect(await store.load(path) == nil)
    }
}

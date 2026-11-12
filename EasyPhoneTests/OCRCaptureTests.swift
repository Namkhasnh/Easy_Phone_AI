import Foundation
import Testing
@testable import EasyPhoneAI

/// 1D.1 — UI_SCREENS S09 step 1, S18 camera explainer / denied fallback "Chọn ảnh có sẵn" (D-185).
@MainActor
@Suite("S09 photo capture")
struct OCRCaptureTests {
    @Test func opensChoosing() {
        let vm = OCRCaptureViewModel(permissions: MockPermissionManager(), cameraAvailable: true)
        #expect(vm.mode == .choosing && vm.imageData == nil && !vm.showsCamera && !vm.showsLibrary)
    }

    @Test func cameraNeverAskedShowsExplainerThenCamera() async {
        let perms = MockPermissionManager([.camera: .notDetermined], answer: .granted)
        let vm = OCRCaptureViewModel(permissions: perms, cameraAvailable: true)
        vm.chooseCamera()
        #expect(vm.pendingPermission == PendingPermission(capability: .camera, variant: .explainer))
        #expect(!vm.showsCamera && perms.requested.isEmpty)                      // never asked before S18
        await vm.allowPermission()
        #expect(perms.requested == [.camera] && vm.showsCamera && vm.pendingPermission == nil)
    }

    @Test func cameraRefusedShowsDeniedWithLibraryFallback() async {
        let perms = MockPermissionManager([.camera: .notDetermined], answer: .denied)
        let vm = OCRCaptureViewModel(permissions: perms, cameraAvailable: true)
        vm.chooseCamera()
        await vm.allowPermission()
        #expect(vm.pendingPermission == PendingPermission(capability: .camera, variant: .denied))
        vm.useLibraryInstead()                                                   // "Chọn ảnh có sẵn"
        #expect(vm.showsLibrary && vm.pendingPermission == nil && !vm.showsCamera)
    }

    @Test func grantedCameraOpensAtOnce() {
        let vm = OCRCaptureViewModel(permissions: MockPermissionManager([.camera: .granted]), cameraAvailable: true)
        vm.chooseCamera()
        #expect(vm.showsCamera && vm.pendingPermission == nil)
    }

    @Test func libraryNeedsNoPermission() {
        let perms = MockPermissionManager([.photos: .notDetermined])
        let vm = OCRCaptureViewModel(permissions: perms, cameraAvailable: false)
        vm.chooseLibrary()
        #expect(vm.showsLibrary && vm.pendingPermission == nil && perms.requested.isEmpty)
    }

    @Test func photoReceivedThenRetake() async {
        let vm = OCRCaptureViewModel(permissions: MockPermissionManager([.camera: .granted]), cameraAvailable: true)
        vm.chooseCamera()
        await vm.received(Data([0xFF, 0xD8]), fromCamera: true)
        #expect(vm.mode == .captured && vm.imageData == Data([0xFF, 0xD8]) && !vm.showsCamera)
        await vm.retake()
        #expect(vm.mode == .choosing && vm.imageData == nil)
    }

    @Test func s09StringsExist() {
        for key in ["ocr.source.camera", "ocr.source.library", "ocr.tips", "ocr.oneImageNote", "ocr.retake",
                    "perm.camera.fallback"] {
            #expect(UserMessage(key: key).text != key)
        }
        #expect(UserMessage(key: "perm.camera.fallback").text == "Chọn ảnh có sẵn")
    }
}

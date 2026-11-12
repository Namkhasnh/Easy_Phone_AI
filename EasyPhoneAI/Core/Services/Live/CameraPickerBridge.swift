import SwiftUI
import UIKit

/// UI_SCREENS S09 "Chụp ảnh" → `UIImagePickerController` camera (D-014: UIKit only through a representable).
/// Hands back the photo as JPEG data; the image never leaves the device here (D-056).
struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: (Data) -> Void
    let onCancel: () -> Void

    /// False on the Simulator / devices without a camera: S09 then offers only "Chọn ảnh có sẵn".
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// SwiftUI image for a thumbnail of JPEG / HEIC data (keeps `UIImage` out of the Views, D-014).
    static func thumbnail(_ data: Data) -> Image? {
        UIImage(data: data).map { Image(uiImage: $0) }
    }

    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // TODO(spec): JPEG quality / max size are set by 1D.2 / 1D.4 (≤ 2048 px, ≤ 4 MB); 0.85 here.
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) {
                parent.onPhoto(data)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}

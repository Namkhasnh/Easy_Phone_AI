@preconcurrency import MessageUI
import SwiftUI

/// ARCHITECTURE §5.3: `MFMessageComposeViewController` prefilled (spec §6.8 AC2) — the user taps Send in the system UI,
/// the app never sends by itself (D-103, AC4). The delegate result goes back as `ComposerResult` (no MessageUI types
/// leave this file, D-015). 🔒 recipients are device-only numbers (D-056).
struct MessageComposerView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: (ComposerResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.recipients = recipients
        composer.body = body
        composer.messageComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor final class Coordinator: NSObject, @preconcurrency MFMessageComposeViewControllerDelegate {
        var onFinish: (ComposerResult) -> Void
        init(onFinish: @escaping (ComposerResult) -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            onFinish(Self.map(result))
        }

        /// Only `.sent` is a sent message (D-102); anything unknown is a failure, never a success.
        static func map(_ result: MessageComposeResult) -> ComposerResult {
            switch result {
            case .sent: .sent
            case .cancelled: .cancelled
            case .failed: .failed
            @unknown default: .failed
            }
        }
    }
}

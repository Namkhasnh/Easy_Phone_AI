import Foundation

/// SMS / iMessage capability (ARCHITECTURE §4.2). The composer itself is a View bridge (`MessageComposerView`, §5.3).
protocol MessagesService: Sendable {
    /// `MFMessageComposeViewController.canSendText()` — false on Simulator / devices without Messages.
    var canSendText: Bool { get }
}

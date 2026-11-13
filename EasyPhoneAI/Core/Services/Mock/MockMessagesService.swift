import Foundation

/// Fixed `canSendText` for previews and tests (D-206).
final class MockMessagesService: MessagesService {
    let canSendText: Bool
    init(canSendText: Bool = true) { self.canSendText = canSendText }
}

import MessageUI

final class LiveMessagesService: MessagesService {
    var canSendText: Bool { MFMessageComposeViewController.canSendText() }
}

import ChatwootAPI
import ChatwootModels
import ChatwootPush
import Foundation
import UserNotifications

/// Turns the relay's placeholder into the real notification. The push carries only
/// Chatwoot's encrypted notice; the name and text are fetched from the agent's own server.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    // The system calls in on its own queue, and the timeout can race the fetch:
    // `pending` is only touched under the lock, and taken exactly once.
    private let lock = NSLock()
    private var pending: (handler: (UNNotificationContent) -> Void, content: UNNotificationContent)?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        lock.withLock { pending = (contentHandler, request.content) }
        let encrypted = request.content.userInfo[PushPayload.message] as? String
        Task { deliver(await NotificationDetails.load(encrypted: encrypted)) }
    }

    /// Out of time: show whatever is known, which may be the placeholder.
    override func serviceExtensionTimeWillExpire() {
        deliver(nil)
    }

    private func deliver(_ details: NotificationDetails?) {
        let taken = lock.withLock { defer { pending = nil }; return pending }
        guard let (handler, content) = taken else { return }
        let updated = content.mutableCopy() as! UNMutableNotificationContent
        details?.apply(to: updated)
        handler(updated)
    }
}

struct NotificationDetails: Sendable {
    var title: String?
    var body: String
    var conversationID: Int?

    static func load(encrypted: String?) async -> NotificationDetails? {
        guard let encrypted, let message = Data(base64Encoded: encrypted),
              let keys = SharedKeychain.push.read()?.keys,
              let plaintext = try? keys.decrypt(message),
              let notice = try? JSONDecoder().decode(PushNotice.self, from: plaintext) else { return nil }
        // Chatwoot's own wording, such as "A new message is created in conversation #42".
        var details = NotificationDetails(body: notice.title)

        // Only follow links to the server and account this device is signed in to.
        guard let session = SharedKeychain.session.read(), notice.host == session.server.host(),
              notice.accountID == session.accountID, let id = notice.conversationID else { return details }
        details.conversationID = id
        let api = AccountAPI(accountID: session.accountID)
        guard let conversation = try? await ChatwootClient(session: session).send(api.conversation(id)) else { return details }
        details.title = conversation.contact.name
        if let message = conversation.lastMessage, let text = message.text ?? message.attachments.first?.summary {
            details.body = message.isPrivate ? String(localized: "Note: \(text)") : text
        }
        return details
    }

    func apply(to content: UNMutableNotificationContent) {
        if let title { content.title = title }
        content.body = body
        if let conversationID {
            content.threadIdentifier = "conversation-\(conversationID)"
            content.categoryIdentifier = PushPayload.replyCategory
            content.userInfo = [PushPayload.conversationID: conversationID]
        }
    }
}

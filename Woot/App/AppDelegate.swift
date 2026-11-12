import ChatwootAPI
import OSLog
import UIKit
import UserNotifications

/// Receives what only an app delegate gets: the APNs token and notification responses.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let sessions = SessionStore()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reply = UNTextInputNotificationAction(
            identifier: PushPayload.replyAction, title: String(localized: "Reply"), options: [],
            textInputButtonTitle: String(localized: "Send"), textInputPlaceholder: String(localized: "Message")
        )
        center.setNotificationCategories([UNNotificationCategory(identifier: PushPayload.replyCategory, actions: [reply], intentIdentifiers: [])])
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await sessions.push.register(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Logger.push.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// In the foreground, the conversation on screen already shows the message.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let id = notification.request.content.userInfo[PushPayload.conversationID] as? Int
        if let id, sessions.account?.openConversation?.conversationID == id { return [] }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo[PushPayload.conversationID] as? Int else { return }
        if let reply = response as? UNTextInputNotificationResponse {
            await send(reply.userText, to: id)
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            sessions.requestedConversation = id
        }
    }

    /// A reply typed on the notification. If it fails, says so with the text, so nothing is lost.
    private func send(_ text: String, to id: Int) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let account = sessions.account else { return }
        do {
            try await account.send(account.api.send(OutgoingMessage(content: text, isPrivate: false), in: id))
        } catch {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Reply not sent")
            content.body = text
            content.userInfo = [PushPayload.conversationID: id]
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

import Foundation

/// What Chatwoot sends in a browser push: a generic title and a link to the conversation.
/// It carries no names or message text; the extension fetches those from the server.
public struct PushNotice: Decodable, Sendable, Equatable {
    public let title: String
    public let url: URL

    /// The server the link points to, to check it matches the signed-in one.
    public var host: String? { url.host() }

    public var accountID: Int? { number(after: "accounts") }

    /// The conversation's display id, which is the id the API uses.
    public var conversationID: Int? { number(after: "conversations") }

    private func number(after component: String) -> Int? {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: component), index + 1 < parts.count else { return nil }
        return Int(parts[index + 1])
    }
}

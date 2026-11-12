import Foundation
import ChatwootModels

public struct ConversationFilter: Hashable, Sendable {
    public enum Scope: String, Sendable, CaseIterable {
        case mine = "me"
        case unassigned
        case all
    }

    public var scope: Scope
    public var status: Conversation.Status
    /// `nil` means every inbox.
    public var inboxID: Int?

    public init(scope: Scope = .mine, status: Conversation.Status = .open, inboxID: Int? = nil) {
        self.scope = scope
        self.status = status
        self.inboxID = inboxID
    }
}

public struct ConversationPage: Decodable, Sendable {
    public struct Counts: Decodable, Sendable {
        public let mine: Int
        public let unassigned: Int
        public let all: Int

        private enum CodingKeys: String, CodingKey {
            case mine = "mine_count", unassigned = "unassigned_count", all = "all_count"
        }
    }

    public let conversations: [Conversation]
    public let counts: Counts?

    private enum CodingKeys: String, CodingKey { case data }
    private enum DataKeys: String, CodingKey { case payload, meta }

    public init(from decoder: any Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self).nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        conversations = try data.decode([Conversation].self, forKey: .payload)
        counts = try data.decodeIfPresent(Counts.self, forKey: .meta)
    }
}

public struct OutgoingMessage: Sendable {
    public struct File: Sendable {
        public let data: Data
        public let fileName: String
        public let mimeType: String

        public init(data: Data, fileName: String, mimeType: String) {
            self.data = data
            self.fileName = fileName
            self.mimeType = mimeType
        }
    }

    public let content: String
    public let isPrivate: Bool
    public let files: [File]
    /// Lets the realtime echo of this message replace its optimistic placeholder.
    public let echoID: String

    public init(content: String, isPrivate: Bool, files: [File] = [], echoID: String = UUID().uuidString) {
        self.content = content
        self.isPrivate = isPrivate
        self.files = files
        self.echoID = echoID
    }
}

/// The REST calls Woot makes, scoped to one account.
public struct AccountAPI: Sendable {
    public let accountID: Int

    public init(accountID: Int) {
        self.accountID = accountID
    }

    private var base: String { "api/v1/accounts/\(accountID)" }

    public func conversations(_ filter: ConversationFilter, page: Int = 1) -> Endpoint<ConversationPage> {
        var query = [
            URLQueryItem(name: "assignee_type", value: filter.scope.rawValue),
            URLQueryItem(name: "status", value: filter.status.rawValue),
            URLQueryItem(name: "page", value: String(page)),
        ]
        if let inboxID = filter.inboxID {
            query.append(URLQueryItem(name: "inbox_id", value: String(inboxID)))
        }
        return Endpoint(.get, "\(base)/conversations", query: query)
    }

    public func searchConversations(_ text: String, page: Int = 1) -> Endpoint<ConversationPage> {
        Endpoint(.get, "\(base)/conversations/search", query: [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "page", value: String(page)),
        ])
    }

    public func conversation(_ id: Int) -> Endpoint<Conversation> {
        Endpoint(.get, "\(base)/conversations/\(id)")
    }

    /// Returns up to 20 messages, oldest first. Pass the oldest loaded id to page back.
    public func messages(in conversationID: Int, before messageID: Int? = nil) -> Endpoint<[Message]> {
        let query = messageID.map { [URLQueryItem(name: "before", value: String($0))] } ?? []
        return Endpoint(.get, "\(base)/conversations/\(conversationID)/messages", query: query) {
            try JSONDecoder.chatwoot.decode(Payload<[Message]>.self, from: $0).payload
        }
    }

    public func send(_ message: OutgoingMessage, in conversationID: Int) -> Endpoint<Message> {
        let path = "\(base)/conversations/\(conversationID)/messages"
        guard !message.files.isEmpty else {
            return Endpoint(.post, path, body: .json(MessageBody(message)))
        }
        var form = MultipartForm()
        form.append("content", message.content)
        form.append("private", message.isPrivate ? "true" : "false")
        form.append("message_type", "outgoing")
        form.append("echo_id", message.echoID)
        for file in message.files { form.append("attachments[]", file: file) }
        return Endpoint(.post, path, body: form.body)
    }

    public func setStatus(_ status: Conversation.Status, of conversationID: Int) -> Endpoint<Void> {
        Endpoint(.post, "\(base)/conversations/\(conversationID)/toggle_status", body: .json(["status": status.rawValue]))
    }

    public func markRead(_ conversationID: Int) -> Endpoint<Void> {
        Endpoint(.post, "\(base)/conversations/\(conversationID)/update_last_seen")
    }

    public func markUnread(_ conversationID: Int) -> Endpoint<Void> {
        Endpoint(.post, "\(base)/conversations/\(conversationID)/unread")
    }

    public func setTyping(_ isTyping: Bool, isPrivate: Bool, in conversationID: Int) -> Endpoint<Void> {
        Endpoint(.post, "\(base)/conversations/\(conversationID)/toggle_typing_status", body: .json(TypingBody(
            typing_status: isTyping ? "on" : "off",
            is_private: isPrivate
        )))
    }

    public func inboxes() -> Endpoint<[Inbox]> {
        Endpoint(.get, "\(base)/inboxes") { try JSONDecoder.chatwoot.decode(Payload<[Inbox]>.self, from: $0).payload }
    }

    public func contact(_ id: Int) -> Endpoint<Contact> {
        Endpoint(.get, "\(base)/contacts/\(id)") { try JSONDecoder.chatwoot.decode(Payload<Contact>.self, from: $0).payload }
    }

    public func conversations(ofContact id: Int) -> Endpoint<[Conversation]> {
        Endpoint(.get, "\(base)/contacts/\(id)/conversations") {
            try JSONDecoder.chatwoot.decode(Payload<[Conversation]>.self, from: $0).payload
        }
    }

    public func setAvailability(_ availability: Availability) -> Endpoint<Void> {
        Endpoint(.post, "api/v1/profile/availability", body: .json(AvailabilityBody(
            profile: .init(availability: availability, account_id: accountID)
        )))
    }
}

// Request bodies mirror Chatwoot's parameter names, hence the snake_case properties.

private struct MessageBody: Encodable {
    let content: String
    let `private`: Bool
    let message_type = "outgoing"
    let echo_id: String

    init(_ message: OutgoingMessage) {
        content = message.content
        `private` = message.isPrivate
        echo_id = message.echoID
    }
}

private struct TypingBody: Encodable {
    let typing_status: String
    let is_private: Bool
}

private struct AvailabilityBody: Encodable {
    struct Profile: Encodable {
        let availability: Availability
        let account_id: Int
    }

    let profile: Profile
}

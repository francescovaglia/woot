import Foundation

public struct Conversation: Identifiable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        case open, pending, snoozed, resolved
    }

    /// The display id, the number shown in Chatwoot's UI and used in every URL.
    public let id: Int
    public let inboxID: Int
    public var status: Status
    public let contact: Contact
    public var assignee: Participant?
    public var lastMessage: Message?
    public var unreadCount: Int
    public var lastActivityAt: Date
    public let createdAt: Date
    public var agentLastSeenAt: Date?
    public var contactLastSeenAt: Date?
    public let labels: [String]
    public let canReply: Bool

    public init(
        id: Int,
        inboxID: Int,
        status: Status,
        contact: Contact,
        assignee: Participant? = nil,
        lastMessage: Message? = nil,
        unreadCount: Int = 0,
        lastActivityAt: Date,
        createdAt: Date,
        agentLastSeenAt: Date? = nil,
        contactLastSeenAt: Date? = nil,
        labels: [String] = [],
        canReply: Bool = true
    ) {
        self.id = id
        self.inboxID = inboxID
        self.status = status
        self.contact = contact
        self.assignee = assignee
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.lastActivityAt = lastActivityAt
        self.createdAt = createdAt
        self.agentLastSeenAt = agentLastSeenAt
        self.contactLastSeenAt = contactLastSeenAt
        self.labels = labels
        self.canReply = canReply
    }
}

extension Conversation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, status, meta, messages, labels
        case inboxID = "inbox_id"
        case unreadCount = "unread_count"
        case lastActivityAt = "last_activity_at"
        case createdAt = "created_at"
        case agentLastSeenAt = "agent_last_seen_at"
        case contactLastSeenAt = "contact_last_seen_at"
        case lastNonActivityMessage = "last_non_activity_message"
        case canReply = "can_reply"
    }

    private enum MetaKeys: String, CodingKey {
        case sender, assignee
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let meta = try container.nestedContainer(keyedBy: MetaKeys.self, forKey: .meta)
        id = try container.decode(Int.self, forKey: .id)
        inboxID = try container.decode(Int.self, forKey: .inboxID)
        status = try container.decode(Status.self, forKey: .status)
        contact = try meta.decode(Contact.self, forKey: .sender)
        assignee = try meta.decodeIfPresent(Participant.self, forKey: .assignee)
        // The list endpoint sends the last chat message twice; realtime payloads only send `messages`.
        lastMessage = try container.decodeIfPresent(Message.self, forKey: .lastNonActivityMessage)
            ?? container.decodeIfPresent([Message].self, forKey: .messages)?.last
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        lastActivityAt = try container.decode(Date.self, forKey: .lastActivityAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        agentLastSeenAt = try container.decodeTimestampIfPresent(forKey: .agentLastSeenAt)
        contactLastSeenAt = try container.decodeTimestampIfPresent(forKey: .contactLastSeenAt)
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        canReply = try container.decodeIfPresent(Bool.self, forKey: .canReply) ?? true
    }
}

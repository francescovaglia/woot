import Foundation

public struct Message: Identifiable, Hashable, Sendable {
    public enum Kind: Int, Sendable {
        case incoming = 0
        case outgoing = 1
        /// System events such as "Conversation was resolved by Francesco".
        case activity = 2
        case template = 3
    }

    public enum Status: String, Sendable {
        case sent, delivered, read, failed, progress
    }

    public let id: Int
    public let conversationID: Int
    public let kind: Kind
    public let content: String?
    public let isPrivate: Bool
    public let status: Status
    public let createdAt: Date
    public let sender: Participant?
    public let attachments: [Attachment]
    public let isDeleted: Bool
    /// Client-generated id echoed back by the server, used to match optimistic messages.
    public let echoID: String?

    public init(
        id: Int,
        conversationID: Int,
        kind: Kind,
        content: String?,
        isPrivate: Bool = false,
        status: Status = .sent,
        createdAt: Date,
        sender: Participant? = nil,
        attachments: [Attachment] = [],
        isDeleted: Bool = false,
        echoID: String? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.kind = kind
        self.content = content
        self.isPrivate = isPrivate
        self.status = status
        self.createdAt = createdAt
        self.sender = sender
        self.attachments = attachments
        self.isDeleted = isDeleted
        self.echoID = echoID
    }

    public var text: String? {
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return content
    }
}

extension Message: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, content, status, sender, attachments
        case conversationID = "conversation_id"
        case kind = "message_type"
        case isPrivate = "private"
        case createdAt = "created_at"
        case contentAttributes = "content_attributes"
        case echoID = "echo_id"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        conversationID = try container.decode(Int.self, forKey: .conversationID)
        kind = try Kind(rawValue: container.decode(Int.self, forKey: .kind)) ?? .activity
        content = try container.decodeIfPresent(String.self, forKey: .content)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        status = try container.decodeIfPresent(String.self, forKey: .status).flatMap(Status.init) ?? .sent
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sender = try container.decodeIfPresent(Participant.self, forKey: .sender)
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        let attributes = try container.decodeIfPresent([String: JSONValue].self, forKey: .contentAttributes) ?? [:]
        isDeleted = attributes["deleted"] == .bool(true)
        echoID = try container.decodeIfPresent(String.self, forKey: .echoID)
    }
}

public struct Attachment: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case image, audio, video, file, location, fallback, share
        case storyMention = "story_mention"
    }

    public let id: Int
    public let kind: Kind
    public let url: URL?
    public let thumbnailURL: URL?
    public let fileSize: Int?
    public let fileExtension: String?
    public let width: Int?
    public let height: Int?

    public init(id: Int, kind: Kind, url: URL?, thumbnailURL: URL? = nil, fileSize: Int? = nil, fileExtension: String? = nil, width: Int? = nil, height: Int? = nil) {
        self.id = id
        self.kind = kind
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.fileSize = fileSize
        self.fileExtension = fileExtension
        self.width = width
        self.height = height
    }

    /// The last path component of the file URL, which Active Storage keeps as the original name.
    public var fileName: String {
        url?.lastPathComponent.removingPercentEncoding ?? "Attachment"
    }
}

extension Attachment: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, width, height
        case kind = "file_type"
        case url = "data_url"
        case thumbnailURL = "thumb_url"
        case fileSize = "file_size"
        case fileExtension = "extension"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        kind = Kind(rawValue: try container.decodeIfPresent(String.self, forKey: .kind) ?? "") ?? .file
        url = try container.decodeURLIfPresent(forKey: .url)
        thumbnailURL = try container.decodeURLIfPresent(forKey: .thumbnailURL)
        fileSize = try container.decodeIfPresent(Int.self, forKey: .fileSize)
        fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
    }
}

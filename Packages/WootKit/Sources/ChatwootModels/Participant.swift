import Foundation

public enum Availability: String, Codable, Sendable, CaseIterable {
    case online, busy, offline
}

/// Anyone who can author a message: a contact, an agent or a bot.
public struct Participant: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case contact, user
        case agentBot = "agent_bot"
    }

    public let id: Int
    public let kind: Kind
    public let name: String
    public let avatarURL: URL?
    public let availability: Availability?

    public init(id: Int, kind: Kind, name: String, avatarURL: URL? = nil, availability: Availability? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.avatarURL = avatarURL
        self.availability = availability
    }
}

extension Participant: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, type, name, thumbnail
        case availableName = "available_name"
        case avatarURL = "avatar_url"
        case availability = "availability_status"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        kind = Kind(rawValue: try container.decodeIfPresent(String.self, forKey: .type) ?? "") ?? .user
        name = try container.decodeIfPresent(String.self, forKey: .availableName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? ""
        avatarURL = try container.decodeURLIfPresent(forKey: .thumbnail)
            ?? container.decodeURLIfPresent(forKey: .avatarURL)
        availability = try container.decodeIfPresent(String.self, forKey: .availability).flatMap(Availability.init)
    }
}

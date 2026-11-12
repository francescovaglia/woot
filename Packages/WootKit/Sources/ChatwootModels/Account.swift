import Foundation

/// The signed-in agent, as returned by `GET /api/v1/profile` and by sign-in.
public struct Profile: Identifiable, Hashable, Sendable, Decodable {
    public let id: Int
    public let name: String
    public let email: String
    public let avatarURL: URL?
    /// Personal API token. Empty when the account has the API feature disabled.
    public let accessToken: String?
    /// Identifies the agent's private ActionCable stream.
    public let pubsubToken: String
    public let accounts: [AccountMembership]
    /// The account last opened in the dashboard.
    public let activeAccountID: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, email, accounts
        case availableName = "available_name"
        case avatarURL = "avatar_url"
        case accessToken = "access_token"
        case pubsubToken = "pubsub_token"
        case activeAccountID = "account_id"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .availableName)
            ?? container.decode(String.self, forKey: .name)
        email = try container.decode(String.self, forKey: .email)
        avatarURL = try container.decodeURLIfPresent(forKey: .avatarURL)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken).flatMap { $0.isEmpty ? nil : $0 }
        pubsubToken = try container.decode(String.self, forKey: .pubsubToken)
        accounts = try container.decodeIfPresent([AccountMembership].self, forKey: .accounts) ?? []
        activeAccountID = try container.decodeIfPresent(Int.self, forKey: .activeAccountID)
    }

    public init(id: Int, name: String, email: String, avatarURL: URL? = nil, accessToken: String? = nil, pubsubToken: String, accounts: [AccountMembership], activeAccountID: Int? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.avatarURL = avatarURL
        self.accessToken = accessToken
        self.pubsubToken = pubsubToken
        self.accounts = accounts
        self.activeAccountID = activeAccountID
    }
}

public struct AccountMembership: Identifiable, Hashable, Sendable, Decodable {
    public let id: Int
    public let name: String
    public let role: String
    /// What the agent chose. The live presence is in realtime presence events.
    public let availability: Availability

    private enum CodingKeys: String, CodingKey {
        case id, name, role, availability
    }

    public init(id: Int, name: String, role: String, availability: Availability) {
        self.id = id
        self.name = name
        self.role = role
        self.availability = availability
    }
}

public struct Inbox: Identifiable, Hashable, Sendable, Decodable {
    public let id: Int
    public let name: String
    /// e.g. `Channel::WebWidget`, `Channel::Email`, `Channel::Api`.
    public let channelType: String

    private enum CodingKeys: String, CodingKey {
        case id, name
        case channelType = "channel_type"
    }

    public init(id: Int, name: String, channelType: String) {
        self.id = id
        self.name = name
        self.channelType = channelType
    }
}

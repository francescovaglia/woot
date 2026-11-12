import Foundation

public struct Contact: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let email: String?
    public let phoneNumber: String?
    public let avatarURL: URL?
    public let availability: Availability?
    public let lastActivityAt: Date?
    public let createdAt: Date?
    /// Set by Chatwoot itself: location, browser, referrer.
    public let additionalAttributes: [String: JSONValue]
    /// Defined by the account: plan, user id, anything the website sends.
    public let customAttributes: [String: JSONValue]

    public init(
        id: Int,
        name: String,
        email: String? = nil,
        phoneNumber: String? = nil,
        avatarURL: URL? = nil,
        availability: Availability? = nil,
        lastActivityAt: Date? = nil,
        createdAt: Date? = nil,
        additionalAttributes: [String: JSONValue] = [:],
        customAttributes: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.phoneNumber = phoneNumber
        self.avatarURL = avatarURL
        self.availability = availability
        self.lastActivityAt = lastActivityAt
        self.createdAt = createdAt
        self.additionalAttributes = additionalAttributes
        self.customAttributes = customAttributes
    }

    public var city: String? { additionalAttributes["city"]?.stringValue }
    public var country: String? { additionalAttributes["country"]?.stringValue }
    /// ISO 3166-1 alpha-2, e.g. `GB`.
    public var countryCode: String? { additionalAttributes["country_code"]?.stringValue?.uppercased() }

    public var location: String? {
        let parts = [city, country].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    public var browser: String? {
        guard let browser = additionalAttributes["browser"] else { return nil }
        let parts = [browser["browser_name"]?.stringValue, browser["platform_name"]?.stringValue].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " on ")
    }

    public var referrer: URL? {
        additionalAttributes["referer"]?.stringValue.flatMap(URL.init(string:))
    }
}

extension Contact: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, email, thumbnail
        case phoneNumber = "phone_number"
        case availability = "availability_status"
        case lastActivityAt = "last_activity_at"
        case createdAt = "created_at"
        case additionalAttributes = "additional_attributes"
        case customAttributes = "custom_attributes"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        avatarURL = try container.decodeURLIfPresent(forKey: .thumbnail)
        availability = try container.decodeIfPresent(String.self, forKey: .availability).flatMap(Availability.init)
        lastActivityAt = try container.decodeTimestampIfPresent(forKey: .lastActivityAt)
        createdAt = try container.decodeTimestampIfPresent(forKey: .createdAt)
        additionalAttributes = try container.decodeIfPresent([String: JSONValue].self, forKey: .additionalAttributes) ?? [:]
        customAttributes = try container.decodeIfPresent([String: JSONValue].self, forKey: .customAttributes) ?? [:]
    }
}

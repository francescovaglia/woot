import Foundation

extension JSONDecoder {
    /// Decoder matching Chatwoot's wire format: Unix timestamps in seconds.
    ///
    /// Keys are mapped with explicit `CodingKeys` instead of `.convertFromSnakeCase`,
    /// which would also rewrite the keys of free-form attribute dictionaries.
    public static var chatwoot: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

extension JSONEncoder {
    public static var chatwoot: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

extension KeyedDecodingContainer {
    /// Chatwoot sends missing images as empty strings rather than `null`.
    func decodeURLIfPresent(forKey key: Key) throws -> URL? {
        guard let string = try decodeIfPresent(String.self, forKey: key), !string.isEmpty else { return nil }
        return URL(string: string)
    }

    /// Chatwoot uses `0` for timestamps that were never set.
    func decodeTimestampIfPresent(forKey key: Key) throws -> Date? {
        guard let seconds = try decodeIfPresent(Double.self, forKey: key), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

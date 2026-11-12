import ChatwootAPI
import ChatwootPush
import Foundation
import Security

/// Stores one Codable value as a generic password in the keychain group the app shares
/// with its notification extension, readable after first unlock so pushes work while locked.
struct KeychainItem<Value: Codable> {
    let service: String
    let account: String
    /// Nil only for items written before the group existed.
    var accessGroup: String? = SharedKeychain.group

    private var query: [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    func read() -> Value? {
        var query = query
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func write(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        let update = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary
        var status = SecItemUpdate(query as CFDictionary, update)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

struct KeychainError: Error {
    let status: OSStatus
}

/// This device's Web Push keys and where Chatwoot currently sends to.
struct PushRegistration: Codable {
    var keys: WebPushKeys
    var endpoint: URL?
}

enum SharedKeychain {
    /// `$(AppIdentifierPrefix)<bundle id>.shared`, set in both targets' Info.plist.
    static let group = Bundle.main.object(forInfoDictionaryKey: "WootKeychainGroup") as? String
    static let session = KeychainItem<ChatwootSession>(service: "Woot", account: "session")
    static let push = KeychainItem<PushRegistration>(service: "Woot", account: "push")
}

/// Keys shared by the relay, the extension and the app.
enum PushPayload {
    /// The encrypted Web Push message, as the relay forwards it.
    static let message = "m"
    static let conversationID = "conversationID"
    static let replyCategory = "message"
    static let replyAction = "reply"
}

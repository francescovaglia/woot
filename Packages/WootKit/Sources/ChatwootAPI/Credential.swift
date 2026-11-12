import Foundation

/// How requests prove who the agent is.
///
/// A personal API token is the stable choice. Password sign-in falls back to Devise
/// session headers when the account has the API feature disabled and no token is issued.
public enum Credential: Codable, Hashable, Sendable {
    case apiToken(String)
    case session(accessToken: String, client: String, uid: String)

    var headers: [String: String] {
        switch self {
        case .apiToken(let token):
            ["api_access_token": token]
        case .session(let accessToken, let client, let uid):
            ["access-token": accessToken, "client": client, "uid": uid, "token-type": "Bearer"]
        }
    }
}

/// Everything needed to talk to one Chatwoot account as one agent.
public struct ChatwootSession: Codable, Hashable, Sendable {
    public let server: URL
    public let credential: Credential
    public let accountID: Int
    public let userID: Int
    public let pubsubToken: String

    public init(server: URL, credential: Credential, accountID: Int, userID: Int, pubsubToken: String) {
        self.server = server
        self.credential = credential
        self.accountID = accountID
        self.userID = userID
        self.pubsubToken = pubsubToken
    }
}

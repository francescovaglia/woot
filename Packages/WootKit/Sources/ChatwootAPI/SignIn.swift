import Foundation
import ChatwootModels

public struct ServerInfo: Decodable, Sendable {
    public let version: String
}

public enum SignInResult: Sendable {
    case signedIn(ChatwootSession, Profile)
    /// The agent has two-factor authentication on: finish with `verifyTwoFactor`.
    case twoFactorRequired(token: String)
}

extension ChatwootClient {
    /// Accepts what people actually type: `chat.example.com`, a trailing slash, a dashboard URL.
    /// Credentials only travel over HTTPS; plain HTTP is allowed for a server on this machine.
    public static func normalizedServerURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text),
              let host = components.host, !host.isEmpty, !host.contains(" "),
              components.user == nil, components.password == nil
        else { return nil }
        let isLoopback = ["localhost", "127.0.0.1", "::1"].contains(host)
        switch components.scheme?.lowercased() {
        case "https": break
        case "http" where isLoopback: break
        default: return nil
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Confirms the address is a Chatwoot server before asking for credentials.
    public func serverInfo() async throws(ChatwootError) -> ServerInfo {
        do {
            return try await send(Endpoint<ServerInfo>(.get, "api"))
        } catch .decoding, .server(status: 404, _) {
            throw .notChatwoot
        }
    }

    public func signIn(email: String, password: String) async throws(ChatwootError) -> SignInResult {
        try await completeSignIn(body: ["email": email, "password": password])
    }

    public func verifyTwoFactor(token: String, code: String) async throws(ChatwootError) -> SignInResult {
        try await completeSignIn(body: ["mfa_token": token, "otp_code": code])
    }

    /// Signs in with a personal access token from Profile Settings.
    public func signIn(accessToken: String) async throws(ChatwootError) -> SignInResult {
        let credential = Credential.apiToken(accessToken)
        let client = ChatwootClient(server: server, credential: credential, urlSession: urlSession)
        do {
            let profile = try await client.send(.profile)
            return try .signedIn(Self.session(server: server, credential: credential, profile: profile), profile)
        } catch .unauthorized {
            throw .invalidCredentials
        }
    }

    private func completeSignIn(body: [String: String]) async throws(ChatwootError) -> SignInResult {
        let endpoint = Endpoint<SignInResponse>(.post, "auth/sign_in", body: .json(body))
        let response: SignInResponse
        let http: HTTPURLResponse
        do {
            (response, http) = try await sendReturningHeaders(endpoint)
        } catch .unauthorized {
            throw .invalidCredentials
        }

        switch response {
        case .twoFactor(let token):
            return .twoFactorRequired(token: token)
        case .profile(let profile):
            let credential: Credential
            if let token = profile.accessToken {
                credential = .apiToken(token)
            } else if let accessToken = http.value(forHTTPHeaderField: "access-token"),
                      let client = http.value(forHTTPHeaderField: "client"),
                      let uid = http.value(forHTTPHeaderField: "uid") {
                credential = .session(accessToken: accessToken, client: client, uid: uid)
            } else {
                throw .decoding("Sign-in returned neither an access token nor session headers")
            }
            return try .signedIn(Self.session(server: server, credential: credential, profile: profile), profile)
        }
    }

    private static func session(server: URL, credential: Credential, profile: Profile) throws(ChatwootError) -> ChatwootSession {
        guard let account = profile.accounts.first(where: { $0.id == profile.activeAccountID }) ?? profile.accounts.first else {
            throw .server(status: 403, message: String(localized: "This user doesn't belong to any account."))
        }
        return ChatwootSession(server: server, credential: credential, accountID: account.id, userID: profile.id, pubsubToken: profile.pubsubToken)
    }
}

private enum SignInResponse: Decodable, Sendable {
    case profile(Profile)
    case twoFactor(token: String)

    private enum CodingKeys: String, CodingKey {
        case data
        case mfaToken = "mfa_token"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let token = try container.decodeIfPresent(String.self, forKey: .mfaToken) {
            self = .twoFactor(token: token)
        } else {
            self = .profile(try container.decode(Profile.self, forKey: .data))
        }
    }
}

import Foundation
import Testing
@testable import ChatwootAPI
@testable import ChatwootModels

/// Serves canned responses so the client runs end to end without a server.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status: Int
        var body: Data
        var headers: [String: String] = [:]
    }

    nonisolated(unsafe) static var responses: [String: Response] = [:]
    nonisolated(unsafe) static var lastRequestHeaders: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequestHeaders = request.allHTTPHeaderFields ?? [:]
        guard let path = request.url?.path, let stub = Self.responses[path] else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: nil, headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// Serialized because the stub table is shared.
@Suite(.serialized) struct SignInTests {
    let client = ChatwootClient(server: URL(string: "https://chat.example.com")!, urlSession: StubProtocol.session)

    @Test func passwordSignInUsesTheAPIToken() async throws {
        let profile = try fixture("profile")
        StubProtocol.responses = ["/auth/sign_in": .init(status: 200, body: Data("{\"data\":".utf8) + profile + Data("}".utf8))]

        guard case .signedIn(let session, _) = try await client.signIn(email: "alex@example.com", password: "secret") else {
            Issue.record("expected a session")
            return
        }
        #expect(session.credential == .apiToken("token-123"))
        #expect(session.accountID == 7)
        #expect(session.pubsubToken == "pubsub-abc")
    }

    @Test func passwordSignInFallsBackToSessionHeaders() async throws {
        let profile = String(decoding: try fixture("profile"), as: UTF8.self)
            .replacingOccurrences(of: "\"token-123\"", with: "\"\"")
        StubProtocol.responses = ["/auth/sign_in": .init(
            status: 200,
            body: Data("{\"data\":\(profile)}".utf8),
            headers: ["access-token": "a", "client": "c", "uid": "alex@example.com"]
        )]

        guard case .signedIn(let session, _) = try await client.signIn(email: "alex@example.com", password: "secret") else {
            Issue.record("expected a session")
            return
        }
        #expect(session.credential == .session(accessToken: "a", client: "c", uid: "alex@example.com"))
    }

    @Test func twoFactorIsReported() async throws {
        StubProtocol.responses = ["/auth/sign_in": .init(status: 206, body: Data(#"{"mfa_required":true,"mfa_token":"m1"}"#.utf8))]
        guard case .twoFactorRequired(let token) = try await client.signIn(email: "a@b.c", password: "x") else {
            Issue.record("expected a two-factor challenge")
            return
        }
        #expect(token == "m1")
    }

    @Test func wrongPassword() async {
        StubProtocol.responses = ["/auth/sign_in": .init(status: 401, body: Data(#"{"errors":["Invalid login credentials"]}"#.utf8))]
        await #expect(throws: ChatwootError.invalidCredentials) {
            try await client.signIn(email: "a@b.c", password: "x")
        }
    }

    @Test func tokenSignInSendsTheToken() async throws {
        StubProtocol.responses = ["/api/v1/profile": .init(status: 200, body: try fixture("profile"))]
        _ = try await client.signIn(accessToken: "token-123")
        #expect(StubProtocol.lastRequestHeaders["api_access_token"] == "token-123")
    }

    @Test func serverValidation() async throws {
        StubProtocol.responses = ["/api": .init(status: 200, body: Data(#"{"version":"4.19.1"}"#.utf8))]
        #expect(try await client.serverInfo().version == "4.19.1")

        StubProtocol.responses = ["/api": .init(status: 404, body: Data("<html>".utf8))]
        await #expect(throws: ChatwootError.notChatwoot) { try await client.serverInfo() }
    }

    @Test func errorsCarryTheServerMessage() async {
        StubProtocol.responses = ["/api/v1/accounts/7/conversations/1/messages": .init(
            status: 422, body: Data(#"{"error":"Conversation is resolved"}"#.utf8)
        )]
        let authed = ChatwootClient(server: client.server, credential: .apiToken("t"), urlSession: StubProtocol.session)
        await #expect(throws: ChatwootError.server(status: 422, message: "Conversation is resolved")) {
            try await authed.send(AccountAPI(accountID: 7).send(OutgoingMessage(content: "x", isPrivate: false), in: 1))
        }
    }

    @Test func offlineIsItsOwnError() async {
        StubProtocol.responses = [:]
        await #expect(throws: ChatwootError.offline) { try await client.serverInfo() }
    }
}

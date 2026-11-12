import Foundation
import Testing
@testable import ChatwootAPI
@testable import ChatwootModels

@Suite struct EndpointTests {
    let server = URL(string: "https://chat.example.com")!
    let api = AccountAPI(accountID: 7)

    @Test func conversationFilterBecomesQuery() throws {
        let request = api.conversations(ConversationFilter(scope: .unassigned, status: .resolved, inboxID: 2), page: 3)
            .urlRequest(server: server, headers: [:])
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/v1/accounts/7/conversations")
        #expect(Set(components.queryItems ?? []) == [
            URLQueryItem(name: "assignee_type", value: "unassigned"),
            URLQueryItem(name: "status", value: "resolved"),
            URLQueryItem(name: "page", value: "3"),
            URLQueryItem(name: "inbox_id", value: "2"),
        ])
    }

    @Test func textMessageIsJSON() throws {
        let message = OutgoingMessage(content: "Hi", isPrivate: true, echoID: "e1")
        let request = api.send(message, in: 511).urlRequest(server: server, headers: [:])
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(body?["content"] as? String == "Hi")
        #expect(body?["private"] as? Bool == true)
        #expect(body?["message_type"] as? String == "outgoing")
        #expect(body?["echo_id"] as? String == "e1")
    }

    @Test func attachmentsSwitchToMultipart() throws {
        let file = OutgoingMessage.File(data: Data("PNG".utf8), fileName: "a \"quoted\"\r\nX-Evil: 1.png", mimeType: "image/png")
        let request = api.send(OutgoingMessage(content: "See", isPrivate: false, files: [file]), in: 511)
            .urlRequest(server: server, headers: [:])
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary=woot-"))
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains(#"name="attachments[]"; filename="a quotedX-Evil: 1.png""#), "no header injection")
        #expect(body.contains("name=\"private\"\r\n\r\nfalse\r\n"))
        #expect(body.hasSuffix("--\r\n"))
    }

    @Test func availabilityIsNestedUnderProfile() throws {
        let request = api.setAvailability(.busy).urlRequest(server: server, headers: [:])
        #expect(request.url?.path == "/api/v1/profile/availability")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: [String: Any]]
        #expect(body?["profile"]?["availability"] as? String == "busy")
        #expect(body?["profile"]?["account_id"] as? Int == 7)
    }

    @Test func credentialsBecomeHeaders() {
        #expect(Credential.apiToken("t").headers == ["api_access_token": "t"])
        let session = Credential.session(accessToken: "a", client: "c", uid: "u").headers
        #expect(session["access-token"] == "a" && session["client"] == "c" && session["uid"] == "u")
    }

    @Test(arguments: [
        ("chat.example.com", "https://chat.example.com"),
        ("  https://chat.example.com/app/accounts/1/dashboard ", "https://chat.example.com"),
        ("http://localhost:3000/", "http://localhost:3000"),
        ("https://chatwoot", "https://chatwoot"),
        ("https://[::1]:3000", "https://[::1]:3000"),
    ])
    func serverURLNormalization(input: String, expected: String) {
        #expect(ChatwootClient.normalizedServerURL(input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "not a host", "https://", "http://chat.example.com", "ftp://chat.example.com", "https://user:pass@chat.example.com"])
    func invalidServerURLs(input: String) {
        #expect(ChatwootClient.normalizedServerURL(input) == nil)
    }
}

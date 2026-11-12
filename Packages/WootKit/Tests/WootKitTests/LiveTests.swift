import Foundation
import Testing
@testable import ChatwootAPI
@testable import ChatwootModels
@testable import ChatwootRealtime

private let liveServer = ProcessInfo.processInfo.environment["WOOT_LIVE_SERVER"].flatMap(ChatwootClient.normalizedServerURL)
private let liveToken = ProcessInfo.processInfo.environment["WOOT_LIVE_TOKEN"]

/// Read-only checks against a real server. Runs only when both variables are set:
/// `WOOT_LIVE_SERVER=https://chat.example.com WOOT_LIVE_TOKEN=... swift test --filter LiveTests`
@Suite(.enabled(if: liveServer != nil && liveToken != nil))
struct LiveTests {
    private func session() async throws -> ChatwootSession {
        let client = ChatwootClient(server: liveServer!)
        guard case .signedIn(let session, _) = try await client.signIn(accessToken: liveToken!) else {
            throw ChatwootError.invalidCredentials
        }
        return session
    }

    @Test func restRoundTrip() async throws {
        let session = try await session()
        let client = ChatwootClient(session: session)
        let api = AccountAPI(accountID: session.accountID)

        _ = try await client.send(api.inboxes())
        let page = try await client.send(api.conversations(ConversationFilter(scope: .all, status: .open)))
        if let conversation = page.conversations.first {
            _ = try await client.send(api.messages(in: conversation.id))
            _ = try await client.send(api.contact(conversation.contact.id))
        }
    }

    @Test(.timeLimit(.minutes(1))) func realtimeSubscribes() async throws {
        let session = try await session()
        let realtime = RealtimeClient(server: session.server, pubsubToken: session.pubsubToken, accountID: session.accountID, userID: session.userID)
        // Twice, as when the app leaves and returns to the foreground.
        for round in 1...2 {
            var subscribed = false
            for await update in realtime.updates() {
                if case .connected = update {
                    subscribed = true
                    break
                }
            }
            #expect(subscribed, "round \(round) never subscribed")
        }
    }
}

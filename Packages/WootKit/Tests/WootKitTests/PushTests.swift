import Foundation
import Testing
@testable import ChatwootAPI
@testable import ChatwootPush

/// The fixture was encrypted by the `web-push` gem that Chatwoot itself uses.
struct PushTests {
    private struct Vector: Decodable {
        let privateKey: String
        let p256dh: String
        let auth: String
        let body: String
        let plaintext: String
    }

    private let vector = try! JSONDecoder().decode(Vector.self, from: fixture("webpush"))

    private var keys: WebPushKeys {
        WebPushKeys(privateKey: Data(base64URL: vector.privateKey), authSecret: Data(base64URL: vector.auth))
    }

    @Test func decryptsWhatChatwootSends() throws {
        #expect(keys.p256dh == vector.p256dh)
        let plaintext = try keys.decrypt(Data(base64Encoded: vector.body)!)
        #expect(String(decoding: plaintext, as: UTF8.self) == vector.plaintext)

        let notice = try JSONDecoder().decode(PushNotice.self, from: plaintext)
        #expect(notice.host == "chat.example.com")
        #expect(notice.accountID == 3)
        #expect(notice.conversationID == 42)
    }

    @Test func rejectsTamperedOrForeignMessages() {
        var body = Data(base64Encoded: vector.body)!
        body[body.count - 1] ^= 1
        #expect(throws: WebPushError.undecryptable) { try keys.decrypt(body) }
        #expect(throws: WebPushError.undecryptable) { try WebPushKeys.generate().decrypt(Data(base64Encoded: vector.body)!) }
        #expect(throws: WebPushError.malformed) { try keys.decrypt(Data(count: 10)) }
    }

    @Test func freshKeysHaveTheExpectedShape() {
        let keys = WebPushKeys.generate()
        #expect(Data(base64URL: keys.p256dh).count == 65)
        #expect(Data(base64URL: keys.auth).count == 16)
    }

    @Test func subscriptionUsesTheEndpointAsPushToken() throws {
        let endpoint = URL(string: "https://relay.example.com/v1/push/abc")!
        let subscribe = Endpoint<Void>.subscribe(PushSubscription(endpoint: endpoint, p256dh: "k", auth: "a"))
        let body = try JSONSerialization.jsonObject(with: subscribe.body!.data) as! [String: [String: Any]]
        let attributes = body["notification_subscription"]?["subscription_attributes"] as? [String: String]
        #expect(body["notification_subscription"]?["subscription_type"] as? String == "browser_push")
        #expect(attributes == ["endpoint": endpoint.absoluteString, "p256dh": "k", "auth": "a", "push_token": endpoint.absoluteString])

        let unsubscribe = Endpoint<Void>.unsubscribe(endpoint: endpoint)
        #expect(unsubscribe.method == .delete)
        #expect(unsubscribe.query == [URLQueryItem(name: "push_token", value: endpoint.absoluteString)])
    }
}

private extension Data {
    init(base64URL string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self = Data(base64Encoded: base64)!
    }
}

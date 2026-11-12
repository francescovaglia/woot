import AsyncHTTPClient
import Crypto
import Foundation
import NIOCore
import Synchronization

public enum DeliveryResult: Sendable, Equatable {
    case delivered
    /// The app was deleted or the token is no longer valid.
    case gone
    case failed(String)
}

/// Delivers one encrypted Web Push message to one device.
public protocol PushSender: Sendable {
    func send(_ message: Data, to device: Device, expiresAt: Date) async -> DeliveryResult
}

public struct APNsCredentials: Sendable {
    let privateKey: P256.Signing.PrivateKey
    let keyID: String
    let teamID: String
    /// The app's bundle id.
    let topic: String

    public init(pem: String, keyID: String, teamID: String, topic: String) throws {
        privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
        self.keyID = keyID
        self.teamID = teamID
        self.topic = topic
    }
}

/// Sends to Apple over HTTP/2 with token-based authentication.
public final class APNsSender: PushSender {
    private let credentials: APNsCredentials
    private let client: HTTPClient
    private let cachedToken = Mutex<(token: String, issuedAt: Date)?>(nil)

    public init(credentials: APNsCredentials, client: HTTPClient = .shared) {
        self.credentials = credentials
        self.client = client
    }

    public func send(_ message: Data, to device: Device, expiresAt: Date) async -> DeliveryResult {
        let host = device.environment == .production ? "api.push.apple.com" : "api.sandbox.push.apple.com"
        var request = HTTPClientRequest(url: "https://\(host)/3/device/\(device.token)")
        request.method = .POST
        request.headers.add(name: "authorization", value: "bearer \(authenticationToken())")
        request.headers.add(name: "apns-topic", value: credentials.topic)
        request.headers.add(name: "apns-push-type", value: "alert")
        request.headers.add(name: "apns-priority", value: "10")
        request.headers.add(name: "apns-expiration", value: String(Int(expiresAt.timeIntervalSince1970)))
        request.body = .bytes(ByteBuffer(data: Self.payload(for: message)))
        do {
            let response = try await client.execute(request, timeout: .seconds(10))
            if response.status == .ok { return .delivered }
            let body = try await response.body.collect(upTo: 4096)
            let reason = (try? JSONDecoder().decode([String: String].self, from: body))?["reason"] ?? "\(response.status.code)"
            return response.status == .gone || reason == "BadDeviceToken" ? .gone : .failed(reason)
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// The visible text is only a fallback: the app's notification extension decrypts `m`
    /// and replaces it with the contact's name and message.
    static func payload(for message: Data) -> Data {
        let payload: [String: Any] = [
            "aps": ["alert": ["title": "Woot", "body": "New notification"], "sound": "default", "mutable-content": 1],
            "m": message.base64EncodedString(),
        ]
        // A dictionary of strings and numbers always serializes.
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    /// Apple wants the same token reused for up to an hour and refreshed at most every 20 minutes.
    private func authenticationToken() -> String {
        cachedToken.withLock { cached in
            if let cached, Date.now.timeIntervalSince(cached.issuedAt) < 50 * 60 { return cached.token }
            let now = Date.now
            let header = Data(#"{"alg":"ES256","kid":"\#(credentials.keyID)"}"#.utf8).base64URLEncoded
            let claims = Data(#"{"iss":"\#(credentials.teamID)","iat":\#(Int(now.timeIntervalSince1970))}"#.utf8).base64URLEncoded
            let signingInput = "\(header).\(claims)"
            // Signing with a valid P-256 key does not fail.
            let signature = try! credentials.privateKey.signature(for: Data(signingInput.utf8)).rawRepresentation.base64URLEncoded
            let token = "\(signingInput).\(signature)"
            cached = (token, now)
            return token
        }
    }
}

import Foundation
import Hummingbird
import HummingbirdTesting
import Synchronization
import Testing
@testable import PushRelay

final class FakeSender: PushSender {
    let result: DeliveryResult
    let sent = Mutex<[(Data, Device)]>([])

    init(_ result: DeliveryResult) {
        self.result = result
    }

    func send(_ message: Data, to device: Device, expiresAt: Date) async -> DeliveryResult {
        sent.withLock { $0.append((message, device)) }
        return result
    }
}

struct RelayTests {
    let seal = DeviceSeal(secret: Data(repeating: 7, count: 32))
    let token = String(repeating: "ab", count: 32)

    func relay(_ sender: FakeSender) -> Application<RouterResponder<BasicRequestContext>> {
        Application(router: Relay(publicURL: URL(string: "https://push.example.com")!, seal: seal, sender: sender).router())
    }

    @Test func sealedDevicesRoundTripAndResistTampering() {
        let device = Device(token: token, environment: .development)
        let sealed = seal.seal(device)
        #expect(seal.open(sealed) == device)
        #expect(!sealed.contains(token))
        #expect(seal.open(String(sealed.dropLast()) + (sealed.last == "A" ? "B" : "A")) == nil)
        #expect(DeviceSeal(secret: Data(repeating: 8, count: 32)).open(sealed) == nil)
    }

    @Test func registersADeviceAndForwardsItsPushes() async throws {
        let sender = FakeSender(.delivered)
        try await relay(sender).test(.router) { client in
            let registration = #"{"token":"\#(token.uppercased())","environment":"production"}"#
            let endpoint = try await client.execute(uri: "/v1/devices", method: .post, body: ByteBuffer(string: registration)) { response in
                #expect(response.status == .ok)
                return try JSONDecoder().decode([String: URL].self, from: Data(buffer: response.body))["endpoint"]!
            }
            #expect(endpoint.host() == "push.example.com")

            try await client.execute(uri: endpoint.path(), method: .post, headers: [.init("TTL")!: "60"], body: ByteBuffer(string: "ciphertext")) { response in
                #expect(response.status == .created)
            }
        }
        let sent = sender.sent.withLock { $0 }
        #expect(sent.count == 1)
        #expect(sent.first?.0 == Data("ciphertext".utf8))
        #expect(sent.first?.1 == Device(token: token, environment: .production))
    }

    @Test func tellsChatwootWhenADeviceIsGone() async throws {
        let path = "/v1/push/\(seal.seal(Device(token: token, environment: .production)))"
        try await relay(FakeSender(.gone)).test(.router) { client in
            try await client.execute(uri: path, method: .post, body: ByteBuffer(string: "x")) { #expect($0.status == .gone) }
        }
        try await relay(FakeSender(.failed("TooManyRequests"))).test(.router) { client in
            try await client.execute(uri: path, method: .post, body: ByteBuffer(string: "x")) { #expect($0.status == .badGateway) }
        }
    }

    @Test func rejectsBadInput() async throws {
        let sender = FakeSender(.delivered)
        try await relay(sender).test(.router) { client in
            try await client.execute(uri: "/v1/devices", method: .post, body: ByteBuffer(string: #"{"token":"nothex","environment":"production"}"#)) {
                #expect($0.status == .badRequest)
            }
            try await client.execute(uri: "/v1/push/forged", method: .post, body: ByteBuffer(string: "x")) { #expect($0.status == .notFound) }
            let path = "/v1/push/\(seal.seal(Device(token: token, environment: .production)))"
            try await client.execute(uri: path, method: .post, body: ByteBuffer(repeating: 0, count: 5000)) { #expect($0.status == .contentTooLarge) }
            try await client.execute(uri: "/health", method: .get) { #expect($0.status == .ok) }
        }
        #expect(sender.sent.withLock { $0.isEmpty })
    }

    @Test func limitsPushesPerDevice() {
        let limiter = RateLimiter(perMinute: 2)
        let now = Date.now
        #expect(limiter.allow("a", now: now) && limiter.allow("a", now: now))
        #expect(!limiter.allow("a", now: now))
        #expect(limiter.allow("b", now: now))
        #expect(limiter.allow("a", now: now.addingTimeInterval(61)))
    }

    @Test func apnsPayloadAsksTheExtensionToDecrypt() throws {
        let payload = try JSONSerialization.jsonObject(with: APNsSender.payload(for: Data("secret".utf8))) as! [String: Any]
        let aps = payload["aps"] as! [String: Any]
        #expect(aps["mutable-content"] as? Int == 1)
        #expect(payload["m"] as? String == Data("secret".utf8).base64EncodedString())
    }
}

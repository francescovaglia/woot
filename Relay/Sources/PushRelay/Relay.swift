import Foundation
import Hummingbird
import Logging

/// Routes of the relay. Chatwoot posts Web Push messages to `/v1/push/:device`;
/// the app asks `/v1/devices` for that URL once it has an APNs token.
public struct Relay: Sendable {
    let publicURL: URL
    let seal: DeviceSeal
    let sender: any PushSender
    let limiter = RateLimiter(perMinute: 60)

    public init(publicURL: URL, seal: DeviceSeal, sender: any PushSender) {
        self.publicURL = publicURL
        self.seal = seal
        self.sender = sender
    }

    struct Registration: Decodable {
        let token: String
        let environment: APNsEnvironment
    }

    struct Endpoint: ResponseEncodable {
        let endpoint: URL
    }

    public func router() -> Router<BasicRequestContext> {
        let router = Router()
        router.get("health") { _, _ in "ok" }

        router.post("v1/devices") { request, context -> Endpoint in
            let registration = try await request.decode(as: Registration.self, context: context)
            let token = registration.token.lowercased()
            guard (64...200).contains(token.count), token.allSatisfy(\.isHexDigit) else {
                throw HTTPError(.badRequest, message: "Invalid device token")
            }
            let sealed = seal.seal(Device(token: token, environment: registration.environment))
            return Endpoint(endpoint: publicURL.appending(path: "v1/push/\(sealed)"))
        }

        router.post("v1/push/:device") { request, context -> Response in
            let sealed = try context.parameters.require("device")
            guard let device = seal.open(sealed) else { return Response(status: .notFound) }
            guard limiter.allow(sealed) else { return Response(status: .tooManyRequests) }
            // RFC 8030 caps a push message at 4096 bytes, well within APNs' payload limit once encoded.
            let body = try await request.body.collect(upTo: 4096)
            let ttl = request.headers[.init("TTL")!].flatMap(Int.init) ?? 0
            let expiresAt = Date.now.addingTimeInterval(TimeInterval(min(max(ttl, 0), 7 * 24 * 3600)))

            switch await sender.send(Data(buffer: body), to: device, expiresAt: expiresAt) {
            case .delivered:
                return Response(status: .created)
            case .gone:
                // Chatwoot deletes the subscription when the push service answers 410.
                return Response(status: .gone)
            case .failed(let reason):
                context.logger.warning("APNs refused a push", metadata: ["reason": .string(reason)])
                return Response(status: .badGateway)
            }
        }
        return router
    }
}

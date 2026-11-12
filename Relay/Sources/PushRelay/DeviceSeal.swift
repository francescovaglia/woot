import Crypto
import Foundation

/// Which APNs gateway a device token belongs to: debug builds get sandbox tokens.
public enum APNsEnvironment: String, Codable, Sendable {
    case development, production
}

public struct Device: Equatable, Sendable {
    public let token: String
    public let environment: APNsEnvironment
}

/// Turns a device into an opaque, unforgeable path component. The relay keeps no
/// database: everything it needs to deliver a push travels inside the endpoint URL,
/// and only the relay can read or mint one.
public struct DeviceSeal: Sendable {
    private let key: SymmetricKey

    public init(secret: Data) {
        key = SymmetricKey(data: secret)
    }

    public func seal(_ device: Device) -> String {
        let plain = Data("\(device.environment.rawValue):\(device.token)".utf8)
        // ChaChaPoly only fails on a malformed key or nonce, both fixed here.
        return try! ChaChaPoly.seal(plain, using: key).combined.base64URLEncoded
    }

    public func open(_ sealed: String) -> Device? {
        guard let data = Data(base64URL: sealed),
              let box = try? ChaChaPoly.SealedBox(combined: data),
              let plain = try? ChaChaPoly.open(box, using: key) else { return nil }
        let parts = String(decoding: plain, as: UTF8.self).split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let environment = APNsEnvironment(rawValue: parts[0]) else { return nil }
        return Device(token: parts[1], environment: environment)
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    init?(base64URL string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}

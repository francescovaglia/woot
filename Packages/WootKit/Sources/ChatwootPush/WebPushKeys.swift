import CryptoKit
import Foundation

public enum WebPushError: Error, Equatable {
    case malformed
    case undecryptable
}

/// The device's half of a Web Push subscription (RFC 8291). Chatwoot encrypts every
/// notification to these keys, so the relay that carries it to APNs only sees ciphertext.
public struct WebPushKeys: Codable, Sendable, Equatable {
    let privateKey: Data
    let authSecret: Data

    init(privateKey: Data, authSecret: Data) {
        self.privateKey = privateKey
        self.authSecret = authSecret
    }

    public static func generate() -> WebPushKeys {
        WebPushKeys(
            privateKey: P256.KeyAgreement.PrivateKey().rawRepresentation,
            authSecret: SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        )
    }

    /// Uncompressed public key, base64url: the subscription's `p256dh`.
    public var p256dh: String {
        // The stored key was produced by CryptoKit, so it always parses.
        try! P256.KeyAgreement.PrivateKey(rawRepresentation: privateKey).publicKey.x963Representation.base64URLEncoded
    }

    /// The subscription's `auth`.
    public var auth: String { authSecret.base64URLEncoded }

    /// Opens an `aes128gcm` message body (RFC 8188 framing, RFC 8291 keys).
    /// Push messages are small, so only a single record is supported.
    public func decrypt(_ message: Data) throws(WebPushError) -> Data {
        let body = Data(message)
        // salt(16) | record size(4) | key id length(1) | key id (the sender's public key) | ciphertext + tag
        guard body.count > 21 else { throw .malformed }
        let salt = body[0..<16]
        let recordSize = body[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let headerEnd = 21 + Int(body[20])
        guard body.count >= headerEnd + 17, body.count - headerEnd <= recordSize else { throw .malformed }

        do {
            let ownKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
            let senderKey = try P256.KeyAgreement.PublicKey(x963Representation: body[21..<headerEnd])
            let shared = try ownKey.sharedSecretFromKeyAgreement(with: senderKey)

            let keyInfo = Data("WebPush: info\0".utf8) + ownKey.publicKey.x963Representation + senderKey.x963Representation
            let inputKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: authSecret, sharedInfo: keyInfo, outputByteCount: 32)
            let pseudoRandomKey = HKDF<SHA256>.extract(inputKeyMaterial: inputKey, salt: salt)
            let contentKey = HKDF<SHA256>.expand(pseudoRandomKey: pseudoRandomKey, info: Data("Content-Encoding: aes128gcm\0".utf8), outputByteCount: 16)
            let nonce = HKDF<SHA256>.expand(pseudoRandomKey: pseudoRandomKey, info: Data("Content-Encoding: nonce\0".utf8), outputByteCount: 12)

            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce.withUnsafeBytes { Data($0) }),
                ciphertext: body[headerEnd..<(body.count - 16)],
                tag: body[(body.count - 16)...]
            )
            let padded = try AES.GCM.open(box, using: contentKey)
            // The plaintext ends with a 0x02 delimiter (last record) followed by zero padding.
            guard let delimiter = padded.lastIndex(where: { $0 != 0 }), padded[delimiter] == 2 else { throw WebPushError.malformed }
            return Data(padded[..<delimiter])
        } catch {
            throw error as? WebPushError ?? .undecryptable
        }
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

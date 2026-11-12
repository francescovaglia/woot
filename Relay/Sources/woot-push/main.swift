import Foundation
import Hummingbird
import PushRelay

/// Configuration comes from the environment; see the README for each variable.
func required(_ name: String) -> String {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
        fatalError("Missing environment variable \(name)")
    }
    return value
}

let environment = ProcessInfo.processInfo.environment
let pem = try environment["APNS_KEY"] ?? String(contentsOfFile: required("APNS_KEY_PATH"), encoding: .utf8)
guard let secret = Data(base64Encoded: required("RELAY_SECRET")), secret.count == 32 else {
    fatalError("RELAY_SECRET must be 32 random bytes in base64")
}
guard let publicURL = URL(string: required("PUBLIC_URL")) else { fatalError("PUBLIC_URL is not a URL") }

let relay = Relay(
    publicURL: publicURL,
    seal: DeviceSeal(secret: secret),
    sender: APNsSender(credentials: try APNsCredentials(
        pem: pem, keyID: required("APNS_KEY_ID"), teamID: required("APNS_TEAM_ID"), topic: required("APNS_TOPIC")
    ))
)
let app = Application(
    router: relay.router(),
    configuration: .init(address: .hostname("0.0.0.0", port: Int(environment["PORT"] ?? "") ?? 8080))
)
try await app.runService()

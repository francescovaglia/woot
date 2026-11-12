import ChatwootAPI
import ChatwootPush
import Foundation
import OSLog
import UIKit
import UserNotifications

/// Connects Chatwoot's own notifications to this device:
/// APNs token, then an endpoint on the relay, then a Web Push subscription on Chatwoot.
/// Chatwoot decides what to notify from the agent's notification settings.
final class PushRegistrar {
    /// The relay's base URL. Empty in builds without one, which turns push off.
    static let relay = (Bundle.main.object(forInfoDictionaryKey: "WootPushRelay") as? String).flatMap { URL(string: $0) }.flatMap { $0.host() == nil ? nil : $0 }
    /// `development` for debug builds, whose tokens only work with the APNs sandbox.
    static let environment = Bundle.main.object(forInfoDictionaryKey: "WootAPSEnvironment") as? String ?? "production"

    weak var sessions: SessionStore?

    func enable() async {
        guard Self.relay != nil else { return }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Called with every APNs token, which iOS hands out at each launch.
    func register(deviceToken: Data) async {
        guard let relay = Self.relay, let account = sessions?.account else { return }
        var registration = SharedKeychain.push.read() ?? PushRegistration(keys: .generate())
        do {
            // The extension needs the keys before the first push can arrive.
            try SharedKeychain.push.write(registration)
            let endpoint = try await Self.endpoint(on: relay, for: deviceToken)
            try await account.send(.subscribe(PushSubscription(endpoint: endpoint, p256dh: registration.keys.p256dh, auth: registration.keys.auth)))
            if let old = registration.endpoint, old != endpoint {
                try? await account.send(.unsubscribe(endpoint: old))
            }
            registration.endpoint = endpoint
            try SharedKeychain.push.write(registration)
        } catch {
            Logger.push.error("Push registration failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Stops this device's notifications for the account that is signing out.
    func disable(for account: AccountStore) {
        guard var registration = SharedKeychain.push.read(), let endpoint = registration.endpoint else { return }
        registration.endpoint = nil
        try? SharedKeychain.push.write(registration)
        Task { try? await account.send(.unsubscribe(endpoint: endpoint)) }
    }

    private struct EndpointResponse: Decodable {
        let endpoint: URL
    }

    private static func endpoint(on relay: URL, for deviceToken: Data) async throws -> URL {
        var request = URLRequest(url: relay.appending(path: "v1/devices"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "token": deviceToken.map { String(format: "%02x", $0) }.joined(),
            "environment": environment,
        ])
        let (data, response) = try await URLSession.chatwoot.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let endpoint = try JSONDecoder().decode(EndpointResponse.self, from: data).endpoint
        // Chatwoot will post notifications there, so it must stay on the relay over TLS.
        guard endpoint.scheme == "https", endpoint.host() == relay.host() else { throw URLError(.badServerResponse) }
        return endpoint
    }
}

import Foundation

/// Which APNs server accepts this install's device token: `development` (sandbox) or `production`.
///
/// The signing profile decides it, not the build configuration. A Release build run from Xcode is
/// signed with a development profile and gets sandbox tokens; sent to production APNs they fail
/// with BadDeviceToken, the relay answers 410 and Chatwoot drops the subscription after one push.
/// App Store and TestFlight builds carry no embedded profile and are always production.
public enum APSEnvironment {
    public static func of(provisioningProfile data: Data?) -> String {
        guard let data,
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              // The profile is a signed CMS envelope around a plain XML plist.
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let environment = entitlements["aps-environment"] as? String
        else { return "production" }
        return environment
    }

    /// The running app's environment, read from its `embedded.mobileprovision`.
    public static var current: String {
        of(provisioningProfile: Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) })
    }
}

import ChatwootAPI
import ChatwootModels
import Foundation
import Observation
import OSLog

/// Owns sign-in state: restores the saved session at launch and replaces it on sign-in and sign-out.
@Observable
final class SessionStore {
    private(set) var account: AccountStore?

    private let keychain = KeychainItem<ChatwootSession>(service: Bundle.main.bundleIdentifier ?? "woot", account: "session")

    init() {
        if let session = keychain.read() {
            account = AccountStore(session: session, onSignedOut: { [weak self] in self?.signOut() })
        }
    }

    func signIn(_ session: ChatwootSession, profile: Profile) {
        do {
            try keychain.write(session)
        } catch {
            // Still usable for this launch; the next one asks to sign in again.
            Logger.session.error("Keychain write failed: \(error)")
        }
        account = AccountStore(session: session, profile: profile, onSignedOut: { [weak self] in self?.signOut() })
    }

    func signOut() {
        account?.stop()
        account = nil
        keychain.delete()
    }
}

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "woot"
    static let session = Logger(subsystem: subsystem, category: "session")
    static let realtime = Logger(subsystem: subsystem, category: "realtime")
    static let api = Logger(subsystem: subsystem, category: "api")
}

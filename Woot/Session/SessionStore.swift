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
            account = makeAccount(session: session, profile: nil)
        }
    }

    func signIn(_ session: ChatwootSession, profile: Profile) {
        do {
            try keychain.write(session)
        } catch {
            // Still usable for this launch; the next one asks to sign in again.
            Logger.session.error("Keychain write failed: \(error)")
        }
        account = makeAccount(session: session, profile: profile)
    }

    /// A late failure from an old account must not sign out the one that replaced it.
    private func makeAccount(session: ChatwootSession, profile: Profile?) -> AccountStore {
        AccountStore(session: session, profile: profile) { [weak self] in
            if self?.account?.session == session { self?.signOut() }
        }
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

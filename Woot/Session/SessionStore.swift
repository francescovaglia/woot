import ChatwootAPI
import ChatwootModels
import Foundation
import Observation
import OSLog

/// Owns sign-in state: restores the saved session at launch and replaces it on sign-in and sign-out.
@Observable
final class SessionStore {
    private(set) var account: AccountStore?

    private let keychain = KeychainItem<ChatwootSession>(service: "io.tild.woot", account: "session")

    init() {
        if let session = keychain.read() {
            account = AccountStore(session: session, onUnauthorized: { [weak self] in self?.signOut() })
        }
    }

    func signIn(_ session: ChatwootSession, profile: Profile) {
        do {
            try keychain.write(session)
        } catch {
            // Still usable for this launch; the next one asks to sign in again.
            Logger.session.error("Keychain write failed: \(error)")
        }
        account = AccountStore(session: session, profile: profile, onUnauthorized: { [weak self] in self?.signOut() })
    }

    func signOut() {
        account?.stop()
        account = nil
        keychain.delete()
    }
}

extension Logger {
    static let session = Logger(subsystem: "io.tild.woot", category: "session")
    static let realtime = Logger(subsystem: "io.tild.woot", category: "realtime")
    static let api = Logger(subsystem: "io.tild.woot", category: "api")
}

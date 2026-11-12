import ChatwootAPI
import ChatwootModels
import Foundation
import Observation
import OSLog

/// Owns sign-in state: restores the saved session at launch and replaces it on sign-in and sign-out.
@Observable
final class SessionStore {
    private(set) var account: AccountStore? {
        didSet { if account != nil { Task { await push.enable() } } }
    }
    /// A conversation to open, from a tapped notification.
    var requestedConversation: Int?

    let push = PushRegistrar()
    private let keychain = SharedKeychain.session

    init() {
        push.sessions = self
        if let session = keychain.read() ?? Self.migrateLegacySession() {
            account = makeAccount(session: session, profile: nil)
            Task { await push.enable() }
        }
    }

    /// Sessions saved before the keychain group existed live outside it, where the
    /// notification extension can't read them.
    private static func migrateLegacySession() -> ChatwootSession? {
        let legacy = KeychainItem<ChatwootSession>(service: Bundle.main.bundleIdentifier ?? "", account: "session", accessGroup: nil)
        guard let session = legacy.read(), (try? SharedKeychain.session.write(session)) != nil else { return nil }
        legacy.delete()
        return session
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
        if let account { push.disable(for: account) }
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
    static let push = Logger(subsystem: subsystem, category: "push")
}

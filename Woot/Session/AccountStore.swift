import ChatwootAPI
import ChatwootModels
import ChatwootRealtime
import Foundation
import Observation
import OSLog

/// Everything that belongs to one signed-in agent: the API, the realtime connection,
/// and the stores that render it. Realtime events fan out from here.
@Observable
final class AccountStore {
    enum Connection { case connecting, live }

    let session: ChatwootSession
    let api: AccountAPI
    private(set) var profile: Profile?
    private(set) var availability: Availability = .online
    private(set) var connection: Connection = .connecting
    private(set) var inboxes: [Inbox] = []
    /// Contacts currently online, from presence events.
    private(set) var onlineContacts: Set<Int> = []

    @ObservationIgnored private(set) lazy var inbox = InboxStore(account: self)
    @ObservationIgnored private(set) lazy var search = SearchStore(account: self)

    /// The conversation on screen, so it receives its own events and doesn't count as unread.
    @ObservationIgnored weak var openConversation: ConversationStore?

    /// Kept for the whole session so drafts, unsent messages and scroll survive navigation.
    @ObservationIgnored private var conversationStores: [Int: ConversationStore] = [:]
    @ObservationIgnored private let client: ChatwootClient
    @ObservationIgnored private let realtime: RealtimeClient
    @ObservationIgnored private let onSignedOut: () -> Void
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var hasConnected = false

    init(session: ChatwootSession, profile: Profile? = nil, onSignedOut: @escaping () -> Void) {
        self.session = session
        self.profile = profile
        self.onSignedOut = onSignedOut
        api = AccountAPI(accountID: session.accountID)
        client = ChatwootClient(session: session)
        realtime = RealtimeClient(server: session.server, pubsubToken: session.pubsubToken, accountID: session.accountID, userID: session.userID)
        availability = profile?.accounts.first { $0.id == session.accountID }?.availability ?? .online
    }

    var userID: Int { session.userID }

    @discardableResult
    func send<Response>(_ endpoint: Endpoint<Response>) async throws(ChatwootError) -> Response {
        do {
            return try await client.send(endpoint)
        } catch {
            // Never the server's error text: it can echo message content back.
            Logger.api.error("\(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .private) failed: \(error.category, privacy: .public)")
            if error == .unauthorized { Task { await verifySession() } }
            throw error
        }
    }

    func conversationStore(for conversation: Conversation) -> ConversationStore {
        if let store = conversationStores[conversation.id] { return store }
        let store = ConversationStore(conversation: conversation, account: self)
        conversationStores[conversation.id] = store
        evictIdleConversationStores()
        return store
    }

    /// Keeps memory flat in a long session: drops the least recently opened stores
    /// that hold nothing the agent would lose.
    private func evictIdleConversationStores() {
        let limit = 20
        guard conversationStores.count > limit else { return }
        let idle = conversationStores.values
            .filter { $0 !== openConversation && !$0.hasUnsavedWork }
            .sorted { $0.lastOpenedAt < $1.lastOpenedAt }
        for store in idle.prefix(conversationStores.count - limit) {
            conversationStores[store.conversationID] = nil
        }
    }

    func cachedConversationStore(id: Int) -> ConversationStore? {
        conversationStores[id]
    }

    /// Called when the app becomes active.
    func start() {
        guard listener == nil else { return }
        listener = Task {
            for await update in realtime.updates() {
                handle(update)
            }
        }
        guard !hasLoaded else { return }
        hasLoaded = true
        Task {
            await inbox.reload()
            await loadAccountDetails()
        }
    }

    /// Called when the app leaves the foreground, so the agent stops appearing online.
    func stop() {
        listener?.cancel()
        listener = nil
        connection = .connecting
    }

    func setAvailability(_ availability: Availability) async {
        let previous = self.availability
        self.availability = availability
        do {
            try await send(api.setAvailability(availability))
        } catch {
            // Roll back only if no newer choice has been made meanwhile.
            if self.availability == availability { self.availability = previous }
        }
    }

    func inbox(id: Int) -> Inbox? {
        inboxes.first { $0.id == id }
    }

    /// Chatwoot also answers 401 for a missing permission, so a 401 alone doesn't end the session:
    /// it ends only if the profile, which every agent can read, is refused too.
    private func verifySession() async {
        do {
            _ = try await client.send(.profile)
        } catch .unauthorized {
            Logger.session.notice("Credential no longer accepted, signing out")
            onSignedOut()
        } catch {}
    }

    private func loadAccountDetails() async {
        async let profile = try? send(.profile)
        async let inboxes = try? send(api.inboxes())
        if let profile = await profile {
            self.profile = profile
            availability = profile.accounts.first { $0.id == session.accountID }?.availability ?? availability
        }
        if let inboxes = await inboxes { self.inboxes = inboxes }
    }

    private func handle(_ update: RealtimeClient.Update) {
        switch update {
        case .connecting:
            connection = .connecting
        case .connected:
            let isReconnect = hasConnected
            hasConnected = true
            connection = .live
            Logger.realtime.info("Subscribed")
            // Events sent while the socket was down are not replayed.
            if isReconnect {
                Task {
                    await inbox.reload()
                    await openConversation?.reload()
                }
            }
        case .rejected:
            Logger.realtime.error("Subscription rejected")
            Task { await verifySession() }
        case .event(.presence(_, let contacts)):
            onlineContacts = Set(contacts.filter { $0.value == .online }.keys)
        case .event(let event):
            inbox.apply(event)
            // Cached conversations that aren't on screen catch up with `reload()` when reopened.
            openConversation?.apply(event)
        }
    }
}

extension ChatwootError {
    /// A label safe to log: no server-provided text.
    var category: String {
        switch self {
        case .notChatwoot: "not-chatwoot"
        case .invalidCredentials: "invalid-credentials"
        case .unauthorized: "unauthorized"
        case .server(let status, _): "server-\(status)"
        case .offline: "offline"
        case .transport(let code): "transport-\(code.rawValue)"
        case .decoding: "decoding"
        }
    }
}

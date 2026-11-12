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

    /// The conversation on screen, so it receives its own events and doesn't count as unread.
    @ObservationIgnored weak var openConversation: ConversationStore?

    @ObservationIgnored private let client: ChatwootClient
    @ObservationIgnored private let realtime: RealtimeClient
    @ObservationIgnored private let onUnauthorized: () -> Void
    @ObservationIgnored private var listener: Task<Void, Never>?

    init(session: ChatwootSession, profile: Profile? = nil, onUnauthorized: @escaping () -> Void) {
        self.session = session
        self.profile = profile
        self.onUnauthorized = onUnauthorized
        api = AccountAPI(accountID: session.accountID)
        client = ChatwootClient(session: session)
        realtime = RealtimeClient(server: session.server, pubsubToken: session.pubsubToken, accountID: session.accountID, userID: session.userID)
        availability = profile?.accounts.first { $0.id == session.accountID }?.availability ?? .online
    }

    var userID: Int { session.userID }

    /// Sends a request, signing out if the server no longer accepts the credential.
    @discardableResult
    func send<Response>(_ endpoint: Endpoint<Response>) async throws(ChatwootError) -> Response {
        do {
            return try await client.send(endpoint)
        } catch {
            if error == .unauthorized { onUnauthorized() }
            Logger.api.error("\(endpoint.method.rawValue) \(endpoint.path) failed: \(error)")
            throw error
        }
    }

    /// Called when the app becomes active.
    func start() {
        guard listener == nil else { return }
        listener = Task { [realtime] in
            await realtime.start()
            for await update in realtime.updates {
                handle(update)
            }
        }
        Task { await loadAccountDetails() }
    }

    /// Called when the app leaves the foreground, so the agent stops appearing online.
    func stop() {
        listener?.cancel()
        listener = nil
        connection = .connecting
        Task { [realtime] in await realtime.stop() }
    }

    func setAvailability(_ availability: Availability) async {
        let previous = self.availability
        self.availability = availability
        do {
            try await send(api.setAvailability(availability))
        } catch {
            self.availability = previous
        }
    }

    func inbox(id: Int) -> Inbox? {
        inboxes.first { $0.id == id }
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
            connection = .live
            Logger.realtime.info("Subscribed")
            // Anything sent while the socket was down is not replayed.
            Task {
                await inbox.reload()
                await openConversation?.reload()
            }
        case .event(.presence(_, let contacts)):
            onlineContacts = Set(contacts.filter { $0.value == .online }.keys)
        case .event(let event):
            inbox.apply(event)
            openConversation?.apply(event)
        }
    }
}

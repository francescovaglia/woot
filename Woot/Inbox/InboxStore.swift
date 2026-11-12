import ChatwootAPI
import ChatwootModels
import ChatwootRealtime
import Foundation
import Observation

/// The filtered conversation list, kept current by realtime events.
@Observable
final class InboxStore {
    enum Phase: Equatable {
        case loading, loaded
        case failed(ChatwootError)
    }

    var filter = ConversationFilter() {
        didSet { if filter != oldValue { Task { await reload() } } }
    }

    private(set) var conversations: [Conversation] = []
    private(set) var counts: ConversationPage.Counts?
    private(set) var phase = Phase.loading
    private(set) var canLoadMore = false

    @ObservationIgnored private unowned let account: AccountStore
    @ObservationIgnored private var page = 1
    @ObservationIgnored private var generation = 0

    init(account: AccountStore) {
        self.account = account
    }

    func reload() async {
        generation += 1
        let current = generation
        if conversations.isEmpty { phase = .loading }
        do {
            let result = try await account.send(account.api.conversations(filter))
            // A newer filter may have started while this one was loading.
            guard current == generation else { return }
            conversations = result.conversations.sorted(by: Self.newestFirst)
            counts = result.counts
            canLoadMore = !result.conversations.isEmpty
            page = 1
            phase = .loaded
        } catch {
            guard current == generation else { return }
            phase = .failed(error)
        }
    }

    func loadMore() async {
        guard canLoadMore, phase == .loaded else { return }
        let current = generation
        guard let result = try? await account.send(account.api.conversations(filter, page: page + 1)), current == generation else { return }
        page += 1
        canLoadMore = !result.conversations.isEmpty
        for conversation in result.conversations { upsert(conversation) }
    }

    func search(_ text: String) async throws(ChatwootError) -> [Conversation] {
        try await account.send(account.api.searchConversations(text)).conversations
    }

    /// Applies the change at once and rolls it back if the server refuses it.
    @discardableResult
    func setStatus(_ status: Conversation.Status, of conversation: Conversation) async -> Bool {
        var updated = conversation
        updated.status = status
        upsert(updated)
        do {
            try await account.send(account.api.setStatus(status, of: conversation.id))
            return true
        } catch {
            upsert(conversation)
            return false
        }
    }

    func markUnread(_ conversation: Conversation) async {
        var updated = conversation
        updated.unreadCount = max(1, conversation.unreadCount)
        upsert(updated)
        try? await account.send(account.api.markUnread(conversation.id))
    }

    /// Clears the badge locally as soon as a conversation is opened.
    func markRead(_ id: Int) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].unreadCount = 0
    }

    func apply(_ event: RealtimeEvent) {
        switch event {
        case .conversationCreated(let conversation), .conversationChanged(let conversation):
            upsert(conversation)
        case .messageCreated(let message) where message.kind != .activity:
            guard let index = conversations.firstIndex(where: { $0.id == message.conversationID }) else {
                // A conversation outside the loaded page just became active.
                Task { await fetchAndUpsert(message.conversationID) }
                return
            }
            conversations[index].lastMessage = message
            conversations[index].lastActivityAt = message.createdAt
            if message.kind == .incoming, account.openConversation?.conversationID != message.conversationID {
                conversations[index].unreadCount += 1
            }
            conversations.sort(by: Self.newestFirst)
        case .messageCreated, .messageUpdated, .typing, .presence:
            break
        }
    }

    private func fetchAndUpsert(_ id: Int) async {
        guard let conversation = try? await account.send(account.api.conversation(id)) else { return }
        upsert(conversation)
    }

    /// Inserts, updates or removes a conversation depending on whether it still matches the filter.
    private func upsert(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if matches(conversation) {
            let index = conversations.firstIndex { Self.newestFirst(conversation, $0) } ?? conversations.endIndex
            conversations.insert(conversation, at: index)
        }
    }

    private func matches(_ conversation: Conversation) -> Bool {
        guard conversation.status == filter.status else { return false }
        if let inboxID = filter.inboxID, conversation.inboxID != inboxID { return false }
        return switch filter.scope {
        case .mine: conversation.assignee?.id == account.userID
        case .unassigned: conversation.assignee == nil
        case .all: true
        }
    }

    private static func newestFirst(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
        lhs.lastActivityAt > rhs.lastActivityAt
    }
}

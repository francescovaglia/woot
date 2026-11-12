import ChatwootAPI
import ChatwootModels
import Foundation
import Observation

/// Search across the whole account: contacts and conversation numbers, then message text.
/// Lives on the account so the query and results are still there after opening a result.
@Observable
final class SearchStore {
    var query = "" {
        didSet { if query != oldValue { schedule() } }
    }

    private(set) var conversations: [ConversationSearchHit] = []
    private(set) var messages: [Message] = []
    private(set) var isSearching = false
    private(set) var failed = false

    @ObservationIgnored private weak var account: AccountStore?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(account: AccountStore) {
        self.account = account
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Loaded conversations whose contact matches, shown before the server answers.
    var localMatches: [Conversation] {
        let text = trimmedQuery
        guard !text.isEmpty, let account else { return [] }
        return account.inbox.conversations.filter { conversation in
            conversation.contact.name.localizedStandardContains(text)
                || conversation.contact.email?.localizedStandardContains(text) == true
                || String(conversation.id) == text
        }
    }

    private func schedule() {
        task?.cancel()
        let text = trimmedQuery
        guard !text.isEmpty else {
            conversations = []
            messages = []
            isSearching = false
            return
        }
        isSearching = true
        task = Task {
            // Wait for a pause in typing.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let account else { return }
            async let conversations = try? account.send(account.api.searchConversations(text))
            async let messages = try? account.send(account.api.searchMessages(text))
            let (foundConversations, foundMessages) = await (conversations, messages)
            guard !Task.isCancelled else { return }
            self.conversations = foundConversations ?? []
            self.messages = foundMessages ?? []
            failed = foundConversations == nil && foundMessages == nil
            isSearching = false
        }
    }
}

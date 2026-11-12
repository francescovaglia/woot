import ChatwootAPI
import ChatwootModels
import ChatwootRealtime
import Foundation
import Observation

/// One conversation: its messages, the composer, and optimistic sends.
/// Cached by `AccountStore` for the session, so a draft survives leaving the screen.
@Observable
final class ConversationStore {
    /// A message that hasn't been confirmed by the server yet.
    struct Pending: Identifiable {
        let message: OutgoingMessage
        let createdAt: Date
        var failed = false
        var id: String { message.echoID }
    }

    enum Mode { case reply, note }

    let conversationID: Int
    private(set) var conversation: Conversation
    private(set) var messages: [Message] = []
    private(set) var pending: [Pending] = []
    private(set) var isLoading = true
    private(set) var loadError: ChatwootError?
    private(set) var hasOlder = false
    private(set) var contactIsTyping = false

    var draft = "" {
        didSet { draftChanged() }
    }
    var mode = Mode.reply
    var files: [OutgoingMessage.File] = []
    /// Attachments still being read from Photos or Files; sending waits for them.
    var importingFiles = 0
    /// A note waiting for confirmation because using it would replace a typed draft.
    var noteToUse: Message?
    /// For the account's cache, which keeps recently opened conversations.
    private(set) var lastOpenedAt = Date.distantPast

    @ObservationIgnored private weak var account: AccountStore?
    @ObservationIgnored private var isLoadingOlder = false
    @ObservationIgnored private var typingResetTask: Task<Void, Never>?
    @ObservationIgnored private var lastTypingSentAt: Date?
    @ObservationIgnored private var typingStopTask: Task<Void, Never>?

    init(conversation: Conversation, account: AccountStore) {
        self.conversation = conversation
        conversationID = conversation.id
        self.account = account
    }

    /// A draft, attachments or a message not yet confirmed: things that must survive.
    var hasUnsavedWork: Bool {
        !draft.isEmpty || !files.isEmpty || !pending.isEmpty
    }

    func didOpen() {
        lastOpenedAt = .now
    }

    var canSend: Bool {
        importingFiles == 0 && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty)
    }

    /// Fetches the newest page. If it doesn't overlap what's loaded, messages were missed
    /// while offline, so the transcript restarts from the newest page instead of keeping a gap.
    func reload() async {
        guard let account else { return }
        var loaded = false
        do {
            async let latest = account.send(account.api.messages(in: conversationID))
            async let fresh = account.send(account.api.conversation(conversationID))
            let page = try await latest
            conversation = try await fresh
            let newestLoaded = messages.last?.id ?? .max
            if messages.isEmpty || !page.contains(where: { $0.id <= newestLoaded }) {
                messages = []
                hasOlder = page.count >= AccountAPI.messagePageSize
            }
            merge(page)
            loadError = nil
            loaded = true
        } catch {
            // `async let` erases typed throws, but `send` only throws ChatwootError.
            if messages.isEmpty { loadError = error as? ChatwootError ?? .transport(.unknown) }
        }
        isLoading = false
        // Only what the agent actually saw counts as read.
        if loaded, !Task.isCancelled, account.openConversation === self {
            await markRead()
        }
    }

    func loadOlder() async {
        guard let account, hasOlder, !isLoadingOlder, let oldest = messages.first else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        guard let older = try? await account.send(account.api.messages(in: conversationID, before: oldest.id)) else { return }
        hasOlder = older.count >= AccountAPI.messagePageSize
        merge(older)
    }

    func send() {
        guard canSend else { return }
        let message = OutgoingMessage(
            content: draft.trimmingCharacters(in: .whitespacesAndNewlines),
            isPrivate: mode == .note,
            files: files
        )
        stopTyping()
        draft = ""
        files = []
        mode = .reply
        pending.append(Pending(message: message, createdAt: .now))
        Task { await deliver(message) }
    }

    /// Before sending again, checks whether the first attempt reached the server after all,
    /// so a timeout never makes the contact receive the same reply twice.
    func retry(_ item: Pending) async {
        guard let account, let index = pending.firstIndex(where: { $0.id == item.id }) else { return }
        pending[index].failed = false
        if let latest = try? await account.send(account.api.messages(in: conversationID)) {
            merge(latest)
            // The REST API doesn't return echo ids, so match on everything that identifies the send.
            let window = item.createdAt.addingTimeInterval(-5)...item.createdAt.addingTimeInterval(120)
            let delivered = latest.contains {
                $0.kind == .outgoing && $0.sender?.id == account.userID && window.contains($0.createdAt)
                    && $0.isPrivate == item.message.isPrivate
                    && ($0.content ?? "") == item.message.content
                    && $0.attachments.count == item.message.files.count
            }
            if delivered {
                discard(id: item.id)
                return
            }
        }
        await deliver(item.message)
    }

    func discard(_ item: Pending) {
        discard(id: item.id)
    }

    /// Moves a private note, such as an AI-written draft, into the composer as a reply.
    /// Asks first if that would replace something already typed.
    func useAsReply(_ note: Message, confirmed: Bool = false) {
        guard confirmed || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            noteToUse = note
            return
        }
        noteToUse = nil
        draft = note.text ?? ""
        mode = .reply
    }

    func setStatus(_ status: Conversation.Status) async {
        guard let account else { return }
        let previous = conversation
        conversation.status = status
        if await !account.inbox.setStatus(status, of: previous) {
            conversation = previous
        }
    }

    func apply(_ event: RealtimeEvent) {
        switch event {
        case .messageCreated(let message) where message.conversationID == conversationID:
            merge([message])
            if message.kind == .incoming {
                contactIsTyping = false
                if account?.openConversation === self { Task { await markRead() } }
            }
        case .messageUpdated(let message) where message.conversationID == conversationID:
            // Only replace: inserting an old message would break paging with `before`.
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
            }
        case .conversationChanged(let updated) where updated.id == conversationID:
            conversation = updated
        case .typing(let id, let participant, let isTyping, _) where id == conversationID && participant.kind == .contact:
            contactIsTyping = isTyping
            typingResetTask?.cancel()
            // Chatwoot doesn't always send typing_off, for example when the visitor closes the tab.
            if isTyping {
                typingResetTask = Task {
                    try? await Task.sleep(for: .seconds(8))
                    if !Task.isCancelled { contactIsTyping = false }
                }
            }
        default:
            break
        }
    }

    private func deliver(_ message: OutgoingMessage) async {
        guard let account else { return }
        do {
            let sent = try await account.send(account.api.send(message, in: conversationID))
            merge([sent])
            discard(id: message.echoID)
        } catch {
            if let index = pending.firstIndex(where: { $0.id == message.echoID }) {
                pending[index].failed = true
            }
        }
    }

    private func discard(id: String) {
        pending.removeAll { $0.id == id }
    }

    /// Adds or replaces messages by id, keeping chronological order, and retires matching optimistic sends.
    private func merge(_ incoming: [Message]) {
        var byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        for message in incoming { byID[message.id] = message }
        messages = byID.values.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let confirmed = Set(incoming.compactMap(\.echoID))
        pending.removeAll { confirmed.contains($0.id) }
    }

    private func markRead() async {
        guard let account else { return }
        account.inbox.markRead(conversationID)
        try? await account.send(account.api.markRead(conversationID))
    }

    /// Tells the contact we're typing, at most every few seconds, and stops after a pause.
    private func draftChanged() {
        guard mode == .reply, !draft.isEmpty else { return }
        if lastTypingSentAt.map({ Date.now.timeIntervalSince($0) > 4 }) ?? true {
            lastTypingSentAt = .now
            sendTyping(true)
        }
        typingStopTask?.cancel()
        typingStopTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { stopTyping() }
        }
    }

    private func stopTyping() {
        typingStopTask?.cancel()
        guard lastTypingSentAt != nil else { return }
        lastTypingSentAt = nil
        sendTyping(false)
    }

    private func sendTyping(_ isTyping: Bool) {
        guard let account else { return }
        let endpoint = account.api.setTyping(isTyping, isPrivate: false, in: conversationID)
        Task { try? await account.send(endpoint) }
    }
}

import ChatwootAPI
import ChatwootModels
import ChatwootRealtime
import Foundation
import Observation

/// One open conversation: its messages, the composer, and optimistic sends.
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
    private(set) var hasOlder = true
    private(set) var contactIsTyping = false

    var draft = "" {
        didSet { draftChanged() }
    }
    var mode = Mode.reply
    var files: [OutgoingMessage.File] = []

    @ObservationIgnored private unowned let account: AccountStore
    @ObservationIgnored private var isLoadingOlder = false
    @ObservationIgnored private var typingResetTask: Task<Void, Never>?
    @ObservationIgnored private var lastTypingSentAt: Date?
    @ObservationIgnored private var typingStopTask: Task<Void, Never>?

    init(conversation: Conversation, account: AccountStore) {
        self.conversation = conversation
        conversationID = conversation.id
        self.account = account
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty
    }

    func reload() async {
        do {
            async let latest = account.send(account.api.messages(in: conversationID))
            async let fresh = account.send(account.api.conversation(conversationID))
            let loaded = try await latest
            conversation = try await fresh
            merge(loaded)
            hasOlder = loaded.count >= 20
            loadError = nil
        } catch {
            // `async let` erases typed throws, but `send` only throws ChatwootError.
            if messages.isEmpty { loadError = error as? ChatwootError ?? .transport(.unknown) }
        }
        isLoading = false
        await markRead()
    }

    func loadOlder() async {
        guard hasOlder, !isLoadingOlder, let oldest = messages.first else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        guard let older = try? await account.send(account.api.messages(in: conversationID, before: oldest.id)) else { return }
        hasOlder = !older.isEmpty
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

    func retry(_ item: Pending) {
        guard let index = pending.firstIndex(where: { $0.id == item.id }) else { return }
        pending[index].failed = false
        Task { await deliver(item.message) }
    }

    func discard(_ item: Pending) {
        discard(id: item.id)
    }

    private func discard(id: String) {
        pending.removeAll { $0.id == id }
    }

    /// Moves a private note, such as an AI-written draft, into the composer as a reply.
    func useAsReply(_ note: Message) {
        draft = note.text ?? ""
        mode = .reply
    }

    func setStatus(_ status: Conversation.Status) async {
        let previous = conversation
        conversation.status = status
        if await !account.inbox.setStatus(status, of: previous) {
            conversation = previous
        }
    }

    func apply(_ event: RealtimeEvent) {
        switch event {
        case .messageCreated(let message), .messageUpdated(let message):
            guard message.conversationID == conversationID else { return }
            merge([message])
            if message.kind == .incoming {
                contactIsTyping = false
                Task { await markRead() }
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

    /// Adds or replaces messages by id, keeping chronological order, and retires matching optimistic sends.
    private func merge(_ incoming: [Message]) {
        var byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        for message in incoming { byID[message.id] = message }
        messages = byID.values.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let confirmed = Set(incoming.compactMap(\.echoID))
        pending.removeAll { confirmed.contains($0.id) }
    }

    private func markRead() async {
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
        let endpoint = account.api.setTyping(isTyping, isPrivate: false, in: conversationID)
        Task { try? await account.send(endpoint) }
    }
}

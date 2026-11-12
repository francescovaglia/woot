import ChatwootModels
import QuickLook
import SwiftUI

struct ConversationView: View {
    @Environment(AccountStore.self) private var account
    @Bindable var store: ConversationStore
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var showsContact = false
    @State private var previewURL: URL?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if store.hasOlder, !store.messages.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        // Keyed by the oldest message so it fires again if it stays visible after a page loads.
                        .task(id: store.messages.first?.id) { await store.loadOlder() }
                }
                transcript
                ForEach(store.pending) { pending in
                    PendingBubble(pending: pending, onRetry: { Task { await store.retry(pending) } }, onDiscard: { store.discard(pending) })
                }
                if store.contactIsTyping {
                    TypingBubble()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaBar(edge: .top) { banner }
        .safeAreaBar(edge: .bottom) {
            if store.conversation.canReply {
                Composer(store: store)
            }
        }
        .overlay { loadingState }
        .navigationTitle(store.conversation.contact.name)
        .navigationSubtitle(store.conversation.contact.email ?? account.inbox(id: store.conversation.inboxID)?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showsContact) {
            ContactView(contact: store.conversation.contact, isOnline: account.onlineContacts.contains(store.conversation.contact.id))
        }
        .quickLookPreview($previewURL)
        .confirmationDialog("Replace your draft with this note?", isPresented: Binding(
            get: { store.noteToUse != nil },
            set: { if !$0 { store.noteToUse = nil } }
        ), titleVisibility: .visible) {
            Button("Replace Draft", role: .destructive) {
                if let note = store.noteToUse { store.useAsReply(note, confirmed: true) }
            }
        }
        .task {
            account.openConversation = store
            await store.reload()
        }
        .onDisappear {
            if account.openConversation === store { account.openConversation = nil }
        }
        .onChange(of: store.messages.last?.id) { scrollToBottom() }
        .onChange(of: store.pending.count) { scrollToBottom() }
    }

    private var transcript: some View {
        let messages = store.messages
        return ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
            let previous = index > 0 ? messages[index - 1] : nil
            if previous.map({ !Calendar.current.isDate($0.createdAt, inSameDayAs: message.createdAt) }) ?? true {
                DaySeparator(date: message.createdAt)
            }
            MessageRow(
                message: message,
                startsGroup: previous?.sender != message.sender || previous?.kind == .activity || previous?.isPrivate == true,
                isSeen: message.id == lastSeenOutgoingID,
                onOpen: open,
                onUseAsReply: { store.useAsReply($0) }
            )
        }
    }

    /// The newest outgoing message the contact has seen, which carries the "Seen" label.
    private var lastSeenOutgoingID: Int? {
        guard let seenAt = store.conversation.contactLastSeenAt else { return nil }
        return store.messages.last { $0.kind == .outgoing && !$0.isPrivate && $0.createdAt <= seenAt }?.id
    }

    @ViewBuilder
    private var banner: some View {
        switch store.conversation.status {
        case .resolved:
            StatusBanner(text: "This conversation is resolved.", action: "Reopen", tint: .green) {
                Task { await store.setStatus(.open) }
            }
        case .pending:
            StatusBanner(text: "Pending: a bot is handling it.", action: "Open", tint: .orange) {
                Task { await store.setStatus(.open) }
            }
        case .snoozed:
            StatusBanner(text: "Snoozed.", action: "Reopen", tint: .indigo) {
                Task { await store.setStatus(.open) }
            }
        case .open:
            EmptyView()
        }
    }

    @ViewBuilder
    private var loadingState: some View {
        if store.isLoading, store.messages.isEmpty {
            ProgressView()
        } else if let error = store.loadError {
            ContentUnavailableView {
                Label("Couldn't load messages", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await store.reload() } }
                    .buttonStyle(.glass)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if store.conversation.status != .resolved {
                Button("Resolve", systemImage: "checkmark") {
                    Task { await store.setStatus(.resolved) }
                }
                .tint(.green)
            }
            Button("Contact", systemImage: "person.crop.circle") { showsContact = true }
        }
    }

    private func scrollToBottom() {
        withAnimation(.snappy) { scrollPosition.scrollTo(edge: .bottom) }
    }

    /// Downloads an attachment under its own name so Quick Look can show and share it.
    private func open(_ attachment: Attachment) {
        guard let url = attachment.url else { return }
        Task {
            guard let (temporary, _) = try? await URLSession.shared.download(from: url) else { return }
            let destination = FileManager.default.temporaryDirectory
                .appending(path: "\(attachment.id)", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let file = destination.appending(path: attachment.fileName)
            try? FileManager.default.removeItem(at: file)
            guard (try? FileManager.default.moveItem(at: temporary, to: file)) != nil else { return }
            previewURL = file
        }
    }
}

private struct StatusBanner: View {
    let text: LocalizedStringKey
    let action: LocalizedStringKey
    let tint: Color
    let perform: () -> Void

    var body: some View {
        HStack {
            Text(text).font(.subheadline.weight(.medium))
            Spacer()
            Button(action, action: perform)
                .buttonStyle(.glassProminent)
                .tint(tint)
                .controlSize(.small)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(tint.opacity(0.25)), in: .capsule)
        .padding(.horizontal)
    }
}

private struct PendingBubble: View {
    let pending: ConversationStore.Pending
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(pending.message.files) { file in
                Label(file.fileName, systemImage: "paperclip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !pending.message.content.isEmpty {
                Text(pending.message.content)
                    .foregroundStyle(pending.message.isPrivate ? Color.primary : .white)
                    .bubble(fill: pending.message.isPrivate ? .yellow.opacity(0.25) : .accentColor)
                    .opacity(pending.failed ? 1 : 0.6)
            }
            if pending.failed {
                HStack {
                    Button("Retry", action: onRetry)
                    Button("Delete", role: .destructive, action: onDiscard)
                }
                .font(.caption.weight(.medium))
                Label("Not sent", systemImage: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
    }
}

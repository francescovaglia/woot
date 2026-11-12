import ChatwootAPI
import ChatwootModels
import SwiftUI

struct InboxView: View {
    @Environment(AccountStore.self) private var account
    @State private var path: [Int] = []
    @State private var showsSettings = false

    var body: some View {
        @Bindable var search = account.search
        NavigationStack(path: $path) {
            Group {
                if search.trimmedQuery.isEmpty {
                    ConversationList()
                } else {
                    SearchResultsView()
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
            .searchable(text: $search.query, prompt: "Name, email or message")
            .navigationDestination(for: Int.self) { id in
                ConversationScreen(id: id)
            }
            .sheet(isPresented: $showsSettings) { SettingsView() }
        }
    }

    private var title: String {
        account.inbox.filter.inboxID.flatMap(account.inbox(id:))?.name ?? String(localized: "Inbox")
    }

    private var subtitle: String {
        if account.connection == .connecting { return String(localized: "Connecting…") }
        let filter = account.inbox.filter
        return "\(filter.scope.title) · \(filter.status.title)"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var inbox = account.inbox
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Inbox", selection: $inbox.filter.inboxID) {
                    Label("All Inboxes", systemImage: "tray.2").tag(Int?.none)
                    ForEach(account.inboxes) { item in
                        Label(item.name, systemImage: item.symbol).tag(Optional(item.id))
                    }
                }
            } label: {
                Label("Inboxes", systemImage: "tray.2")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Assigned", selection: $inbox.filter.scope) {
                    ForEach(ConversationFilter.Scope.allCases, id: \.self) { scope in
                        Label(scope.title, systemImage: scope.symbol)
                    }
                }
                Picker("Status", selection: $inbox.filter.status) {
                    ForEach(Conversation.Status.allCases, id: \.self) { status in
                        Label(status.title, systemImage: status.symbol)
                    }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease")
            }
        }
        ToolbarItem(placement: .bottomBar) {
            Button { showsSettings = true } label: {
                AvatarView(name: account.profile?.name ?? "", url: account.profile?.avatarURL, size: 30)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(account.availability.color)
                            .frame(width: 10, height: 10)
                            .overlay { Circle().stroke(.background, lineWidth: 1.5) }
                    }
            }
            .accessibilityLabel("Settings, \(account.availability.title)")
        }
    }
}

/// The filtered list. Its own view, so typing in search doesn't re-render every row.
private struct ConversationList: View {
    @Environment(AccountStore.self) private var account

    var body: some View {
        let store = account.inbox
        List {
            ForEach(store.conversations) { conversation in
                NavigationLink(value: conversation.id) {
                    ConversationRow(conversation: conversation, isOnline: account.onlineContacts.contains(conversation.contact.id))
                }
                .swipeActions(edge: .trailing) { StatusAction(conversation: conversation) }
                .swipeActions(edge: .leading) {
                    if conversation.unreadCount == 0 {
                        Button("Unread", systemImage: "message.badge") {
                            Task { await store.markUnread(conversation) }
                        }
                        .tint(.blue)
                    }
                }
                .contextMenu { StatusAction(conversation: conversation) }
                .onAppear {
                    if conversation.id == store.conversations.last?.id {
                        Task { await store.loadMore() }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await store.reload() }
        .overlay { emptyState }
    }

    @ViewBuilder
    private var emptyState: some View {
        let store = account.inbox
        if !store.conversations.isEmpty {
            EmptyView()
        } else if case .failed(let error) = store.phase {
            ContentUnavailableView {
                Label("Couldn't load conversations", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await store.reload() } }
                    .buttonStyle(.glass)
            }
        } else if store.phase == .loading {
            ProgressView()
        } else {
            ContentUnavailableView(
                "All caught up",
                systemImage: "tray",
                description: Text("No \(store.filter.status.title.lowercased()) conversations here.")
            )
        }
    }
}

private struct StatusAction: View {
    @Environment(AccountStore.self) private var account
    let conversation: Conversation

    var body: some View {
        if conversation.status == .resolved {
            Button("Reopen", systemImage: "arrow.uturn.backward") {
                Task { await account.inbox.setStatus(.open, of: conversation) }
            }
            .tint(.orange)
        } else {
            Button("Resolve", systemImage: "checkmark") {
                Task { await account.inbox.setStatus(.resolved, of: conversation) }
            }
            .tint(.green)
        }
    }
}

/// Opens a conversation by number: from the cache, from the loaded list, or from the server.
struct ConversationScreen: View {
    @Environment(AccountStore.self) private var account
    let id: Int
    @State private var store: ConversationStore?
    @State private var error: ChatwootError?

    var body: some View {
        Group {
            if let store {
                ConversationView(store: store)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't open conversation", systemImage: "exclamationmark.bubble")
                } description: {
                    Text(error.localizedDescription)
                }
            } else {
                ProgressView()
            }
        }
        .task(id: id) { await resolve() }
    }

    private func resolve() async {
        if let cached = account.cachedConversationStore(id: id) ?? account.inbox.conversation(id: id).map(account.conversationStore) {
            store = cached
            return
        }
        do throws(ChatwootError) {
            let conversation = try await account.send(account.api.conversation(id))
            store = account.conversationStore(for: conversation)
        } catch {
            self.error = error
        }
    }
}

extension ConversationFilter.Scope {
    var title: String {
        switch self {
        case .mine: String(localized: "Mine")
        case .unassigned: String(localized: "Unassigned")
        case .all: String(localized: "All")
        }
    }

    var symbol: String {
        switch self {
        case .mine: "person"
        case .unassigned: "person.badge.plus"
        case .all: "person.2"
        }
    }
}

extension Conversation.Status {
    var title: String {
        switch self {
        case .open: String(localized: "Open")
        case .pending: String(localized: "Pending")
        case .snoozed: String(localized: "Snoozed")
        case .resolved: String(localized: "Resolved")
        }
    }

    var symbol: String {
        switch self {
        case .open: "tray"
        case .pending: "hourglass"
        case .snoozed: "moon.zzz"
        case .resolved: "checkmark.circle"
        }
    }
}

extension Inbox {
    var symbol: String {
        switch channelType {
        case "Channel::Email": "envelope"
        case "Channel::Whatsapp", "Channel::TwilioSms", "Channel::Sms": "phone.bubble"
        case "Channel::Telegram", "Channel::Line", "Channel::FacebookPage", "Channel::Instagram": "paperplane"
        case "Channel::Api": "chevron.left.forwardslash.chevron.right"
        default: "bubble.left.and.bubble.right"
        }
    }
}

extension Availability {
    var title: String {
        switch self {
        case .online: String(localized: "Online")
        case .busy: String(localized: "Busy")
        case .offline: String(localized: "Offline")
        }
    }

    var color: Color {
        switch self {
        case .online: .green
        case .busy: .orange
        case .offline: .gray
        }
    }
}

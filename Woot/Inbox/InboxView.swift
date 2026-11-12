import ChatwootAPI
import ChatwootModels
import SwiftUI

struct InboxView: View {
    @Environment(AccountStore.self) private var account
    @State private var path: [Conversation] = []
    @State private var query = ""
    @State private var searchResults: [Conversation]?
    @State private var showsSettings = false

    private var store: InboxStore { account.inbox }

    var body: some View {
        NavigationStack(path: $path) {
            list
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                .toolbar { toolbar }
                .searchable(text: $query, prompt: "Search conversations")
                .task(id: query) { await search() }
                .refreshable { await store.reload() }
                .task { await store.reload() }
                .navigationDestination(for: Conversation.self) { conversation in
                    ConversationView(conversation: conversation, account: account)
                }
                .sheet(isPresented: $showsSettings) { SettingsView() }
        }
    }

    private var title: String {
        store.filter.inboxID.flatMap(account.inbox(id:))?.name ?? String(localized: "Inbox")
    }

    private var subtitle: String {
        if account.connection == .connecting { return String(localized: "Connecting…") }
        return "\(store.filter.scope.title) · \(store.filter.status.title)"
    }

    @ViewBuilder
    private var list: some View {
        let conversations = searchResults ?? store.conversations
        List {
            ForEach(conversations) { conversation in
                NavigationLink(value: conversation) {
                    ConversationRow(conversation: conversation, isOnline: account.onlineContacts.contains(conversation.contact.id))
                }
                .swipeActions(edge: .trailing) { statusAction(for: conversation) }
                .swipeActions(edge: .leading) {
                    if conversation.unreadCount == 0 {
                        Button("Unread", systemImage: "message.badge") {
                            Task { await store.markUnread(conversation) }
                        }
                        .tint(.blue)
                    }
                }
                .contextMenu { statusAction(for: conversation) }
                .onAppear {
                    if searchResults == nil, conversation.id == conversations.last?.id {
                        Task { await store.loadMore() }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay { emptyState(isEmpty: conversations.isEmpty) }
    }

    @ViewBuilder
    private func statusAction(for conversation: Conversation) -> some View {
        if conversation.status == .resolved {
            Button("Reopen", systemImage: "arrow.uturn.backward") {
                Task { await store.setStatus(.open, of: conversation) }
            }
            .tint(.orange)
        } else {
            Button("Resolve", systemImage: "checkmark") {
                Task { await store.setStatus(.resolved, of: conversation) }
            }
            .tint(.green)
        }
    }

    @ViewBuilder
    private func emptyState(isEmpty: Bool) -> some View {
        if searchResults != nil, isEmpty {
            ContentUnavailableView.search(text: query)
        } else if case .failed(let error) = store.phase, isEmpty {
            ContentUnavailableView {
                Label("Couldn't load conversations", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await store.reload() } }
                    .buttonStyle(.glass)
            }
        } else if store.phase == .loading, isEmpty {
            ProgressView()
        } else if isEmpty {
            ContentUnavailableView(
                "All caught up",
                systemImage: "tray",
                description: Text("No \(store.filter.status.title.lowercased()) conversations here.")
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var store = store
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Inbox", selection: $store.filter.inboxID) {
                    Label("All Inboxes", systemImage: "tray.2").tag(Int?.none)
                    ForEach(account.inboxes) { inbox in
                        Label(inbox.name, systemImage: inbox.symbol).tag(Optional(inbox.id))
                    }
                }
            } label: {
                Label("Inboxes", systemImage: "tray.2")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Assigned", selection: $store.filter.scope) {
                    ForEach(ConversationFilter.Scope.allCases, id: \.self) { scope in
                        Label(scope.title, systemImage: scope.symbol)
                    }
                }
                Picker("Status", selection: $store.filter.status) {
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

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            searchResults = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searchResults = (try? await store.search(text)) ?? []
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

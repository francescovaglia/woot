import ChatwootAPI
import ChatwootModels
import SwiftUI

/// Contacts first, matched instantly against what's loaded and then by the server,
/// followed by messages that contain the text.
struct SearchResultsView: View {
    @Environment(AccountStore.self) private var account

    var body: some View {
        let search = account.search
        let local = search.localMatches
        let localIDs = Set(local.map(\.id))
        let remote = search.conversations.filter { !localIDs.contains($0.id) }

        List {
            if !local.isEmpty || !remote.isEmpty {
                Section("Conversations") {
                    ForEach(local) { conversation in
                        NavigationLink(value: conversation.id) {
                            ConversationRow(conversation: conversation)
                        }
                        .accessibilityIdentifier("searchResult")
                    }
                    ForEach(remote) { hit in
                        NavigationLink(value: hit.id) {
                            ContactHitRow(hit: hit)
                        }
                        .accessibilityIdentifier("searchResult")
                    }
                }
            }
            if !search.messages.isEmpty {
                Section("Messages") {
                    ForEach(search.messages) { message in
                        NavigationLink(value: message.conversationID) {
                            MessageHitRow(message: message, contactName: contactName(for: message.conversationID), query: search.trimmedQuery)
                        }
                        .accessibilityIdentifier("searchResult")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if local.isEmpty, remote.isEmpty, search.messages.isEmpty {
                if search.isSearching {
                    ProgressView()
                } else if search.failed {
                    ContentUnavailableView("Couldn't search", systemImage: "wifi.exclamationmark", description: Text("Check your connection and try again."))
                } else {
                    ContentUnavailableView.search(text: search.trimmedQuery)
                }
            }
        }
    }
}

extension SearchResultsView {
    /// The contact of a message's conversation, when search or the inbox already knows it.
    private func contactName(for conversationID: Int) -> String? {
        account.search.conversations.first { $0.id == conversationID }?.contact.name
            ?? account.inbox.conversation(id: conversationID)?.contact.name
    }
}

private struct ContactHitRow: View {
    let hit: ConversationSearchHit

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: hit.contact.name, url: hit.contact.avatarURL, size: 40, countryCode: hit.contact.countryCode)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.contact.name).font(.headline).lineLimit(1)
                Text([hit.contact.email, hit.inboxName].compactMap(\.self).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("#\(hit.id)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct MessageHitRow: View {
    let message: Message
    let contactName: String?
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if message.isPrivate {
                    Image(systemName: "note.text").foregroundStyle(.orange)
                } else if message.kind == .outgoing {
                    Image(systemName: "arrowshape.turn.up.left").foregroundStyle(.secondary)
                }
                Text(contactName ?? String(localized: "Conversation #\(message.conversationID)"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(message.createdAt.inboxTimestamp)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(highlighted)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    /// The snippet around the first match, starting on a word, with every match in bold.
    private var highlighted: AttributedString {
        let text = (message.text ?? "").replacingOccurrences(of: "\n", with: " ")
        var start = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
            .map { text.index($0.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex } ?? text.startIndex
        if start > text.startIndex, let space = text[start...].firstIndex(of: " ") {
            start = text.index(after: space)
        }
        var snippet = AttributedString((start > text.startIndex ? "…" : "") + text[start...])
        var searchRange = snippet.startIndex..<snippet.endIndex
        while let match = snippet[searchRange].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            snippet[match].font = .subheadline.bold()
            snippet[match].foregroundColor = .primary
            searchRange = match.upperBound..<snippet.endIndex
        }
        return snippet
    }
}

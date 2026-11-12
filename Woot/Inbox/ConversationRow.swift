import ChatwootModels
import SwiftUI

struct ConversationRow: View {
    let conversation: Conversation
    var isOnline = false

    private var isUnread: Bool { conversation.unreadCount > 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(
                name: conversation.contact.name,
                url: conversation.contact.avatarURL,
                countryCode: conversation.contact.countryCode,
                isOnline: isOnline
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.contact.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(conversation.lastActivityAt.inboxTimestamp)
                        .font(.subheadline)
                        .foregroundStyle(isUnread ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .monospacedDigit()
                }

                HStack(alignment: .top) {
                    preview
                        .font(.subheadline)
                        .foregroundStyle(isUnread ? .primary : .secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isUnread {
                        Text(conversation.unreadCount, format: .number)
                            .font(.caption.bold())
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.tint, in: .capsule)
                            .accessibilityLabel("\(conversation.unreadCount) unread")
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var preview: some View {
        if let message = conversation.lastMessage {
            let text = message.text ?? message.attachments.first.map(Self.describe) ?? ""
            if message.isPrivate {
                Text("\(Image(systemName: "note.text")) \(text)")
            } else if message.kind == .outgoing {
                Text("\(Image(systemName: "arrowshape.turn.up.left")) \(text)")
            } else {
                Text(text)
            }
        } else {
            Text("No messages yet").italic()
        }
    }

    private static func describe(_ attachment: Attachment) -> String {
        switch attachment.kind {
        case .image: String(localized: "Photo")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .location: String(localized: "Location")
        default: attachment.fileName
        }
    }
}

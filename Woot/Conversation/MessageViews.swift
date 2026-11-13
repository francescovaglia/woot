import ChatwootModels
import SwiftUI

/// One entry in the transcript, decided by the message kind.
struct MessageRow: View {
    let message: Message
    /// First message of a run from the same sender: shows the name above the bubble.
    let startsGroup: Bool
    let isSeen: Bool
    let onOpen: (Attachment) -> Void
    let onUseAsReply: (Message) -> Void

    var body: some View {
        switch message.kind {
        case .unknown:
            EmptyView()
        case .activity:
            ActivityLine(text: message.text ?? "")
        case _ where message.isPrivate && !message.isDeleted:
            NoteBubble(message: message, onOpen: onOpen, onUseAsReply: onUseAsReply)
        default:
            Bubble(message: message, startsGroup: startsGroup, isSeen: isSeen, onOpen: onOpen)
        }
    }
}

private struct Bubble: View {
    let message: Message
    let startsGroup: Bool
    let isSeen: Bool
    let onOpen: (Attachment) -> Void

    private var isMine: Bool { message.kind == .outgoing || message.kind == .template }

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            if startsGroup, let name = message.sender?.name {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
            ForEach(message.attachments) { attachment in
                AttachmentView(attachment: attachment, onOpen: onOpen)
            }
            if message.isDeleted {
                Text("This message was deleted")
                    .italic()
                    .foregroundStyle(.secondary)
                    .bubble(fill: Color(.secondarySystemFill))
            } else if let text = message.text {
                MarkdownText(text)
                    .foregroundStyle(isMine ? .white : .primary)
                    .tint(isMine ? .white : .accentColor)
                    .bubble(fill: isMine ? Color.accentColor : Color(.secondarySystemFill))
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                    }
            }
            if isSeen {
                Label("Seen", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else if message.status == .failed {
                Label("Not delivered", systemImage: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .padding(isMine ? .leading : .trailing, 48)
    }
}

/// A private note sits on the agents' side like a reply, but in yellow and labelled,
/// so it never reads as something the contact saw.
private struct NoteBubble: View {
    let message: Message
    let onOpen: (Attachment) -> Void
    let onUseAsReply: (Message) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Label(message.sender.map { "Note by \($0.name)" } ?? String(localized: "Private note"), systemImage: "note.text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            ForEach(message.attachments) { attachment in
                AttachmentView(attachment: attachment, onOpen: onOpen)
            }
            if let text = message.text {
                MarkdownText(text)
                    .bubble(fill: Color.yellow.opacity(0.22))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.yellow.opacity(0.5)) }
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                        Button("Use as Reply", systemImage: "arrowshape.turn.up.left") { onUseAsReply(message) }
                    }
                Button("Use as Reply", systemImage: "arrowshape.turn.up.left") { onUseAsReply(message) }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
    }
}

private struct ActivityLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}

struct DaySeparator: View {
    let date: Date

    var body: some View {
        Text(date.daySeparator)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
    }
}

struct TypingBubble: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 7, height: 7)
                    .opacity(phase ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(index) * 0.15), value: phase)
            }
        }
        .foregroundStyle(.secondary)
        .bubble(fill: Color(.secondarySystemFill))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { phase = true }
        .accessibilityLabel("Typing")
    }
}

/// Chatwoot stores messages as Markdown; inline styles and links are rendered, the rest stays text.
struct MarkdownText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        Text((try? AttributedString(markdown: source, options: options)) ?? AttributedString(source))
    }
}

extension View {
    func bubble(fill: Color) -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(fill, in: .rect(cornerRadius: 20))
    }
}

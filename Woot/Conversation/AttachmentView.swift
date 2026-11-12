import ChatwootModels
import SwiftUI

struct AttachmentView: View {
    let attachment: Attachment
    let onOpen: (Attachment) -> Void

    var body: some View {
        Button { onOpen(attachment) } label: {
            switch attachment.kind {
            case .image:
                image
            default:
                file
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attachment.fileName)
    }

    private var image: some View {
        let ratio = attachment.width.flatMap { width in attachment.height.map { CGFloat(width) / CGFloat(max($0, 1)) } } ?? 4 / 3
        return AsyncImage(url: attachment.thumbnailURL ?? attachment.url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .aspectRatio(ratio, contentMode: .fit)
        .frame(maxWidth: 240, maxHeight: 320)
        .clipShape(.rect(cornerRadius: 18))
    }

    private var file: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let size = attachment.fileSize {
                    Text(size.fileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: 260, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 16))
    }

    private var symbol: String {
        switch attachment.kind {
        case .video: "play.rectangle"
        case .audio: "waveform"
        case .location: "mappin.and.ellipse"
        default: "doc"
        }
    }
}

import ChatwootAPI
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The reply bar: attachments, a reply or private-note toggle, and the text field.
struct Composer: View {
    @Bindable var store: ConversationStore
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showsPhotoPicker = false
    @State private var showsFileImporter = false
    @FocusState private var isFocused: Bool

    private var isNote: Bool { store.mode == .note }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isNote {
                Label("Private note, only agents can see it", systemImage: "note.text")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .transition(.opacity)
            }
            if !store.files.isEmpty {
                attachmentChips
            }
            HStack(alignment: .bottom, spacing: 8) {
                attachMenu
                TextField(isNote ? "Private note" : "Reply", text: $store.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(isNote ? .regular.tint(.yellow.opacity(0.35)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 22))
                Button(action: store.send) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(isNote ? .orange : .accentColor)
                .disabled(!store.canSend)
                .accessibilityLabel(isNote ? "Add note" : "Send")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .animation(.snappy, value: store.mode)
        .animation(.snappy, value: store.files.count)
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoSelection, maxSelectionCount: 10, matching: .any(of: [.images, .videos]))
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true, onCompletion: importFiles)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await importPhotos(items) }
        }
    }

    private var attachMenu: some View {
        Menu {
            Picker("Mode", selection: $store.mode) {
                Label("Reply", systemImage: "arrowshape.turn.up.left").tag(ConversationStore.Mode.reply)
                Label("Private Note", systemImage: "note.text").tag(ConversationStore.Mode.note)
            }
            Divider()
            Button("Photo Library", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
            Button("Files", systemImage: "folder") { showsFileImporter = true }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Attach or switch to a note")
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(Array(store.files.enumerated()), id: \.offset) { index, file in
                    HStack(spacing: 6) {
                        Image(systemName: file.mimeType.hasPrefix("image/") ? "photo" : "doc")
                        Text(file.fileName).lineLimit(1).frame(maxWidth: 140)
                        Button("Remove", systemImage: "xmark.circle.fill") { store.files.remove(at: index) }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                }
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first ?? .jpeg
            let name = "Photo-\(store.files.count + 1).\(type.preferredFilenameExtension ?? "jpg")"
            store.files.append(.init(data: data, fileName: name, mimeType: type.preferredMIMEType ?? "application/octet-stream"))
        }
    }

    private func importFiles(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let type = UTType(filenameExtension: url.pathExtension)
            store.files.append(.init(data: data, fileName: url.lastPathComponent, mimeType: type?.preferredMIMEType ?? "application/octet-stream"))
        }
    }
}

import ChatwootModels
import MapKit
import SwiftUI

/// The contact card, laid out like Contacts: a map of where they are, then their details.
struct ContactView: View {
    let contact: Contact
    let isOnline: Bool

    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var place: MKMapItem?
    @State private var details: Contact?
    @State private var history: [Conversation] = []

    private var shown: Contact { details ?? contact }

    var body: some View {
        NavigationStack {
            List {
                Section { header }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                Section {
                    if let email = shown.email {
                        LabeledLink("Email", value: email, url: Self.url(scheme: "mailto", path: email))
                    }
                    if let phone = shown.phoneNumber {
                        LabeledLink("Phone", value: phone, url: Self.url(scheme: "tel", path: phone.filter { $0.isNumber || $0 == "+" }))
                    }
                    if let location = shown.location {
                        LabeledContent("Location") {
                            Text([location, shown.countryCode.flatMap(AvatarView.flag)].compactMap(\.self).joined(separator: " "))
                        }
                    }
                    if let timeZone = place?.timeZone {
                        LabeledContent("Local time") {
                            Text(Date.now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)))
                        }
                    }
                    if let browser = shown.browser {
                        LabeledContent("Browser", value: browser)
                    }
                    if let referrer = shown.referrer {
                        LabeledLink("Came from", value: referrer.host() ?? referrer.absoluteString, url: referrer)
                    }
                }

                let attributes = shown.customAttributes.compactMapValues(\.displayText).sorted { $0.key < $1.key }
                if !attributes.isEmpty {
                    Section("Attributes") {
                        ForEach(attributes, id: \.key) { key, value in
                            LabeledContent(key.replacingOccurrences(of: "_", with: " ").capitalized, value: value)
                        }
                    }
                }

                if history.count > 1 {
                    Section("Conversations") {
                        ForEach(history) { conversation in
                            LabeledContent {
                                Text(conversation.status.title)
                            } label: {
                                Text(conversation.lastMessage?.text ?? "#\(conversation.id)").lineLimit(1)
                                Text(conversation.lastActivityAt, format: .dateTime.day().month().year())
                            }
                        }
                    }
                }
            }
            .listSectionSpacing(.compact)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Group {
                if let place {
                    Map(initialPosition: .region(MKCoordinateRegion(center: place.location.coordinate, latitudinalMeters: 400_000, longitudinalMeters: 400_000)), interactionModes: []) {
                        Marker(shown.city ?? "", coordinate: place.location.coordinate)
                    }
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(height: 150)
            .clipShape(.rect(cornerRadius: 24))

            AvatarView(name: shown.name, url: shown.avatarURL, size: 84, isOnline: isOnline)
                .overlay { Circle().stroke(.background, lineWidth: 4) }
                .offset(y: -48)
                .padding(.bottom, -48)

            Text(shown.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if let lastActivity = shown.lastActivityAt {
                Text("Last seen \(lastActivity, format: .relative(presentation: .named))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
    }

    /// Builds `mailto:` and `tel:` links from contact data without letting it add query parameters.
    private static func url(scheme: String, path: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.path = path
        return components.url
    }

    private func load() async {
        async let details = try? account.send(account.api.contact(contact.id))
        async let history = try? account.send(account.api.conversations(ofContact: contact.id))
        self.details = await details
        self.history = await history ?? []
        if let location = shown.location, let request = MKGeocodingRequest(addressString: location) {
            place = try? await request.mapItems.first
        }
    }
}

private struct LabeledLink: View {
    let label: LocalizedStringKey
    let value: String
    let url: URL?

    init(_ label: LocalizedStringKey, value: String, url: URL?) {
        self.label = label
        self.value = value
        self.url = url
    }

    var body: some View {
        LabeledContent(label) {
            if let url {
                Link(value, destination: url)
            } else {
                Text(value)
            }
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
        }
    }
}

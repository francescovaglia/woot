import ChatwootModels
import SwiftUI

struct SettingsView: View {
    @Environment(AccountStore.self) private var account
    @Environment(SessionStore.self) private var sessions
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AvatarView(name: account.profile?.name ?? "", url: account.profile?.avatarURL, size: 56)
                        VStack(alignment: .leading) {
                            Text(account.profile?.name ?? "").font(.headline)
                            Text(account.profile?.email ?? "").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Picker("Availability", selection: Binding(
                        get: { account.availability },
                        set: { value in Task { await account.setAvailability(value) } }
                    )) {
                        ForEach(Availability.allCases, id: \.self) { availability in
                            Label {
                                Text(availability.title)
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(availability.color)
                            }
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Availability")
                } footer: {
                    Text("While Woot is open you also appear online to Chatwoot's live presence.")
                }

                Section("Server") {
                    LabeledContent("Address", value: account.session.server.host() ?? account.session.server.absoluteString)
                    if let name = account.profile?.accounts.first(where: { $0.id == account.session.accountID })?.name {
                        LabeledContent("Account", value: name)
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) { confirmsSignOut = true }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                }
            }
            .confirmationDialog("Sign out of \(account.session.server.host() ?? "Chatwoot")?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    sessions.signOut()
                }
            }
        }
    }
}

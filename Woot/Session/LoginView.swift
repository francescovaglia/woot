import ChatwootAPI
import ChatwootModels
import SwiftUI

struct LoginView: View {
    private enum Method { case password, token }
    private enum Field { case server, email, password, token, code }

    @Environment(SessionStore.self) private var sessions
    @AppStorage("lastServer") private var server = ""
    @State private var email = ""
    @State private var password = ""
    @State private var token = ""
    @State private var code = ""
    @State private var method = Method.password
    @State private var twoFactorToken: String?
    @State private var isWorking = false
    @State private var error: String?
    @FocusState private var focus: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("chat.example.com", text: $server)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .server)
                        .accessibilityIdentifier("server")
                        .submitLabel(.next)
                        .onSubmit { focus = method == .password ? .email : .token }
                } header: {
                    Text("Chatwoot server")
                }

                if let twoFactorToken {
                    Section {
                        TextField("123456", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .focused($focus, equals: .code)
                    } header: {
                        Text("Two-factor code")
                    } footer: {
                        Text("Enter the code from your authenticator app, or a backup code.")
                    }
                    .onAppear { focus = .code }
                    .id(twoFactorToken)
                } else if method == .password {
                    Section {
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(signIn)
                    } footer: {
                        Button("Use an access token instead") { method = .token }
                            .accessibilityIdentifier("useToken")
                            .font(.footnote)
                    }
                } else {
                    Section {
                        SecureField("Access token", text: $token)
                            // Not a password: keeps iOS from offering to save it in Passwords.
                            .textContentType(.oneTimeCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .token)
                            .accessibilityIdentifier("token")
                            .submitLabel(.go)
                            .onSubmit(signIn)
                    } footer: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Find it in Chatwoot under Profile Settings, Access Token.")
                            Button("Use email and password instead") { method = .password }
                        }
                        .font(.footnote)
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Woot")
            // A safe-area bar rises with the keyboard; a bottom toolbar would sit behind it.
            .safeAreaBar(edge: .bottom) {
                Button(action: signIn) {
                    Group {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text(twoFactorToken == nil ? "Sign In" : "Verify")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!canSubmit || isWorking)
                .accessibilityIdentifier("signIn")
                .padding()
            }
            .disabled(isWorking)
            .animation(.default, value: method)
            .animation(.default, value: twoFactorToken)
            .onAppear { focus = server.isEmpty ? .server : .email }
        }
    }

    private var canSubmit: Bool {
        guard ChatwootClient.normalizedServerURL(server) != nil else { return false }
        if twoFactorToken != nil { return !code.isEmpty }
        return method == .password ? !email.isEmpty && !password.isEmpty : !token.isEmpty
    }

    private func signIn() {
        guard canSubmit, let url = ChatwootClient.normalizedServerURL(server) else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            let client = ChatwootClient(server: url)
            do {
                let result: SignInResult
                if let twoFactorToken {
                    result = try await client.verifyTwoFactor(token: twoFactorToken, code: code)
                } else {
                    _ = try await client.serverInfo()
                    result = method == .password
                        ? try await client.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
                        : try await client.signIn(accessToken: token.trimmingCharacters(in: .whitespaces))
                }
                switch result {
                case .signedIn(let session, let profile):
                    server = url.absoluteString
                    sessions.signIn(session, profile: profile)
                case .twoFactorRequired(let token):
                    twoFactorToken = token
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

#Preview {
    LoginView().environment(SessionStore())
}

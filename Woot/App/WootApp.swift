import SwiftUI

@main
struct WootApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(delegate.sessions)
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let account = sessions.account {
                InboxView()
                    .environment(account)
                    .id(account.session)
            } else {
                LoginView()
            }
        }
        // Links in messages and contact details come from strangers: only web, mail and phone open.
        .environment(\.openURL, OpenURLAction { url in
            ["https", "http", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
        })
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Realtime presence makes the agent look online, so it only runs in the foreground.
            if phase == .active { sessions.account?.start() } else if phase == .background { sessions.account?.stop() }
        }
        .onChange(of: sessions.account?.session) { _, session in
            if session != nil, scenePhase == .active { sessions.account?.start() }
        }
    }
}

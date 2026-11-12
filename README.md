# Woot

A native iOS client for [Chatwoot](https://www.chatwoot.com), the open source customer support platform.
Built with SwiftUI for iOS 27; the app has no third-party dependencies.

Woot works with any Chatwoot server, self-hosted or cloud, from version 4.

## Features

- **Sign in** with email and password, two-factor authentication, or a personal access token.
- **Inbox** filtered by assignee (mine, unassigned, all), status and inbox, with unread counts.
- **Search** across the whole account: contacts, emails, conversation numbers and message text.
- **Conversations** with attachments, Markdown, private notes, typing indicators and read receipts.
  Any private note can become the reply in one tap, handy when a bot or an AI drafts answers as notes.
- **Live updates** over Chatwoot's ActionCable connection, with reconnection and gap recovery.
- **Contact card** with location, local time, browser and custom attributes.
- **Push notifications** with the contact's name and message, tap to open, reply from the notification.
- Drafts, unsent messages and search survive navigation; failed sends can be retried without duplicates.

## Architecture

```
Packages/WootKit        Swift package, no dependencies
  ChatwootModels        Codable models for REST, realtime and webhook payloads
  ChatwootAPI           Typed endpoints and a client with typed errors
  ChatwootRealtime      ActionCable over URLSessionWebSocketTask, as an AsyncStream
  ChatwootPush          Web Push keys and decryption (RFC 8291)
Woot/                   The app: one @Observable store per screen, SwiftUI views
WootNotifications/      Notification service extension
Shared/                 Code both of them use: keychain items, payload keys
Relay/                  woot-push, the Cloudflare Worker that hands notifications to APNs
WootUITests/            End-to-end checks against a real server
```

Every request is an `Endpoint<Response>` value that can be inspected without the network,
which is how most of the API is tested. The app owns state in a few `@Observable` stores:
`AccountStore` holds the session and fans realtime events out to `InboxStore`, `SearchStore`
and the `ConversationStore` on screen.

## Push notifications

Chatwoot can't reach APNs itself, but it already sends Web Push to any endpoint a user
subscribes. Woot uses that, so Chatwoot keeps deciding who gets notified, from each agent's
own notification settings, and nothing needs configuring on the server:

```
Chatwoot ──Web Push, encrypted to the device──▶ woot-push ──▶ APNs ──▶ extension ──▶ your server
```

1. The app gets an APNs token and asks the relay for an endpoint. The endpoint carries the token
   sealed with the relay's key, so the relay keeps no database.
2. The app subscribes that endpoint on Chatwoot with keys generated on the device.
3. Chatwoot encrypts each notification to those keys. The relay forwards the ciphertext to APNs
   without being able to read it, and answers `410` once the app is gone so Chatwoot drops it.
4. The extension decrypts it, then fetches the contact's name and message from your server.

Apple only accepts pushes for an app signed with the APNs key of the team that ships it, so the
official build uses our relay. The relay can't read what it carries, and its code is the
Worker in `Relay/`.

### Run your own relay

If you build Woot with your own Apple developer account, you can run your own relay on
Cloudflare Workers' free plan:

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/francescovaglia/woot/tree/main/Relay)

1. In [Apple Developer > Keys](https://developer.apple.com/account/resources/authkeys/list), create a key
   with Apple Push Notifications service enabled and download the `.p8` file.
2. Press the button. When asked, paste the contents of the `.p8` as `APNS_KEY`, its Key ID as `APNS_KEY_ID`,
   your Team ID as `APNS_TEAM_ID`, your app's bundle id as `APNS_TOPIC`, and the output of
   `openssl rand -base64 32` as `RELAY_SECRET`.
3. Put the Worker's address in `Config/Local.xcconfig` as `WOOT_PUSH_RELAY` and build the app.

Keep `RELAY_SECRET` stable: changing it invalidates every endpoint until apps register again,
which they do at each launch. With an empty `WOOT_PUSH_RELAY`, the app builds with notifications off.

## Building

Requirements: Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cp Config/Local.example.xcconfig Config/Local.xcconfig   # set your team and bundle id
xcodegen generate
open Woot.xcodeproj
```

## Testing

```sh
cd Packages/WootKit && swift test
cd Relay && npm install && npm test
```

Two suites talk to a real server and are skipped unless you provide one. They only read data.

```sh
WOOT_LIVE_SERVER=https://chat.example.com WOOT_LIVE_TOKEN=<token> swift test --filter LiveTests
```

The UI tests need the same values, passed to the test runner with the `TEST_RUNNER_` prefix.
They open conversations and type in private-note mode, so contacts never see a typing indicator.

## Roadmap

Planned, roughly in order. Ideas and pull requests are welcome.

**Working a conversation**
- Assign to an agent or team, snooze, and add labels.
- Canned responses in the composer.
- Edit contact details.

**Notifications**
- Choose what Chatwoot notifies you about, from the app's settings.
- Communication notifications with the contact's avatar, and a Resolve action next to Reply.
- Unread count on the app icon.

**Accounts**
- Several accounts and servers, with a switcher.

**Privacy and quality**
- Hide conversation content in the app switcher.
- Unit tests for the stores, against a fake API.

**Release**
- App Store release under a new name, with screenshots and a demo account.

## License

MIT, see [LICENSE](LICENSE).

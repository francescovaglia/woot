# Woot

A native iOS client for [Chatwoot](https://www.chatwoot.com), the open source customer support platform.
Built with SwiftUI for iOS 27, with no third-party dependencies.

Woot works with any Chatwoot server, self-hosted or cloud, from version 4.

## Features

- **Sign in** with email and password, two-factor authentication, or a personal access token.
- **Inbox** filtered by assignee (mine, unassigned, all), status and inbox, with unread counts.
- **Search** across the whole account: contacts, emails, conversation numbers and message text.
- **Conversations** with attachments, Markdown, private notes, typing indicators and read receipts.
  Any private note can become the reply in one tap, handy when a bot or an AI drafts answers as notes.
- **Live updates** over Chatwoot's ActionCable connection, with reconnection and gap recovery.
- **Contact card** with location, local time, browser and custom attributes.
- Drafts, unsent messages and search survive navigation; failed sends can be retried without duplicates.

## Architecture

```
Packages/WootKit        Swift package, no dependencies
  ChatwootModels        Codable models for REST, realtime and webhook payloads
  ChatwootAPI           Typed endpoints and a client with typed errors
  ChatwootRealtime      ActionCable over URLSessionWebSocketTask, as an AsyncStream
Woot/                   The app: one @Observable store per screen, SwiftUI views
WootUITests/            End-to-end checks against a real server
```

Every request is an `Endpoint<Response>` value that can be inspected without the network,
which is how most of the API is tested. The app owns state in a few `@Observable` stores:
`AccountStore` holds the session and fans realtime events out to `InboxStore`, `SearchStore`
and the `ConversationStore` on screen.

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
```

Two suites talk to a real server and are skipped unless you provide one. They only read data.

```sh
WOOT_LIVE_SERVER=https://chat.example.com WOOT_LIVE_TOKEN=<token> swift test --filter LiveTests
```

The UI tests need the same values, passed to the test runner with the `TEST_RUNNER_` prefix.
They open conversations and type in private-note mode, so contacts never see a typing indicator.

## License

MIT, see [LICENSE](LICENSE).

# Contributing

Thanks for helping. A few rules keep the codebase small and readable:

- **No third-party dependencies** in the app or in WootKit.
- **Swift 6 with strict concurrency**, no warnings. `swift test` in `Packages/WootKit` must pass.
- **Comments say why**, in short English sentences. The code says what.
- **No real customer data** in fixtures, screenshots or test artifacts. Use invented names.
- **One change per pull request**, with a short description of the behavior it changes.

To build, see the README. Live tests need your own Chatwoot server and are never run in CI.

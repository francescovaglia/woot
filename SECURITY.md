# Security

Woot handles support conversations and agent credentials, so security reports are welcome.

**Please don't open a public issue for a vulnerability.** Use GitHub's private reporting
(Security, Report a vulnerability) on this repository. Expect a first answer within a week.

## How Woot treats your data

- The access token lives in the Keychain, on this device only. Signing out deletes it.
- Requests use an ephemeral URL session: no HTTP cache or cookies on disk.
- Credentials are only sent over HTTPS; plain HTTP is accepted for `localhost` alone.
- Everything a Chatwoot server or a customer sends is treated as untrusted: attachment names
  are reduced to a single safe file name, and links open only for web, mail and phone addresses.
- Logs never contain message text or server error bodies.
- Notifications are encrypted by your Chatwoot server to keys that never leave the device.
  The relay that hands them to Apple only sees ciphertext and the device token; the extension
  decrypts them and fetches names and text from your server directly.

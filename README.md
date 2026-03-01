# MailMoi

MailMoi is a native SwiftUI app for iPhone, iPad, and macOS that turns shared links into polished, responsive emails. It uses Gmail OAuth, keeps a durable offline queue, and includes a native Share Extension so links can be sent from the system share sheet without getting dropped.

## Release 0.1

Version `0.1` is the first end-to-end release candidate. It ships the full core workflow:

- Sign in with Gmail using OAuth 2.0 + PKCE.
- Send from the authenticated Gmail account.
- Save a default recipient and reuse recent recipients.
- Compose manually in the app or send from the native share sheet.
- Queue every outbound email locally before network delivery.
- Retry queued emails when the app launches, becomes active, or connectivity returns.
- Share queue state, saved recipients, and session data through the App Group `group.com.niederme.mailmoi`.

The app is built entirely with Apple-native frameworks, including `SwiftUI`, `AuthenticationServices`, `Network`, and `Security`.

## What 0.1 Sends

Each email is sent through the Gmail API with a subject in this format:

```text
<article title> (Sent via MailMoi)
```

For reachable web URLs, MailMoi attempts to enrich the message before sending:

- Uses the page `<title>` when available, with sensible metadata fallbacks.
- Pulls excerpt text when the page exposes a description.
- Generates a short summary when enough content is available.
- Inlines a preview image when the page exposes one and the image fetch succeeds.
- Renders the HTML email as a responsive card layout for desktop and mobile clients.

If metadata lookup fails, MailMoi falls back to the title, excerpt, and URL captured from the app or share sheet.

## Share Extension

The `MailMoiShare` extension is included for iPhone, iPad, and macOS share sheets.

- It reads title, excerpt, and URL from the shared item when the host app provides them.
- If a default recipient is already saved and the share contains enough data, it tries to send immediately.
- If immediate delivery fails, it writes the message into the shared queue and exits cleanly.
- If the host app only supplies a URL, the extension still allows manual editing before queueing.

## Distribution

Release `0.1` is currently set up to ship through TestFlight.

- Xcode Cloud is configured to start on pushes to `main`.
- The active workflow archives both iOS and macOS builds.
- Successful archives are prepared for `TestFlight (Internal Testing Only)`.

That means a merge into `main` should automatically enqueue a new TestFlight build for the current internal testers.

## Local Development

For local development builds:

1. Open [MailMoi.xcodeproj](/Users/niederme/~Repos/mail-moi/MailMoi.xcodeproj) in Xcode.
2. In `Signing & Capabilities`, enable `Automatically manage signing`.
3. Make sure both targets use the same Apple Developer team:
   - `MailMoi`
   - `MailMoiShare`
4. Confirm the App Group capability is enabled for both targets and matches `group.com.niederme.mailmoi`.
5. Run the shared `MailMoi` scheme on iPhone, iPad, or macOS.

The repo already includes a configured OAuth client ID in [GoogleOAuthConfig.swift](/Users/niederme/~Repos/mail-moi/MailMoi/Services/GoogleOAuthConfig.swift). If you are moving this project to a different Google Cloud project, update the client ID there and keep the redirect configuration aligned with [Info.plist](/Users/niederme/~Repos/mail-moi/MailMoi/Info.plist).

## Known Limitations

- Background delivery while the app is fully terminated is not implemented. The queue is durable, but retries resume only after the app launches, becomes active, or the share extension runs again.
- TestFlight distribution is currently configured for internal testing only.
- Command-line builds still require valid provisioning for `com.niederme.MailMoi` and `com.niederme.MailMoi.ShareExtension`. In Xcode, automatic signing handles this; with `xcodebuild`, use `-allowProvisioningUpdates`.

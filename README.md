# MailMoi

MailMoi is a native SwiftUI app for iPhone, iPad, and macOS that turns shared links, posts, and photos into polished, responsive emails. It uses Gmail OAuth, keeps a durable offline queue, and includes a native Share Extension so shares from the system sheet do not get dropped.

## Current Status

MailMoi currently ships the full core workflow:

- Sign in with Gmail using OAuth 2.0 + PKCE.
- Send from the authenticated Gmail account.
- Save a default recipient in its own dedicated settings section and reuse recent recipients.
- Use the app to manage Gmail, recipient defaults, share-sheet behavior, and the offline queue.
- Handle links, pasted post text, and image-only shares as first-class queueable items.
- Queue every outbound email locally before network delivery.
- Retry queued emails when the app launches, becomes active, or connectivity returns.
- Share queue state, saved recipients, and session data through the App Group `group.com.niederme.mailmoi`.
- Let the share sheet either send immediately or stay open with a pre-filled draft, based on the global `Auto-send` setting in the app.
- Use a settings-style form on iPhone and iPad, and a desktop card layout on macOS.

The app is built entirely with Apple-native frameworks, including `SwiftUI`, `AuthenticationServices`, `Network`, `Security`, and `FoundationModels` when available.

## What It Sends

Each email is sent through the Gmail API with a subject in this format:

```text
<article title> (Sent via MailMoi)
```

For reachable web URLs, MailMoi attempts to enrich the message before sending:

- Uses the page `<title>` when available, with sensible metadata fallbacks.
- Pulls a page description when one is available.
- Generates a short summary when enough high-quality body content is available.
- Inlines a preview image when the page exposes one and the image fetch succeeds.
- Renders the HTML email as a responsive card layout for desktop and mobile clients.
- Normalizes common shared-post formats, including X/Twitter share text and Overcast titles, before building the email.
- Promotes real article URLs out of shared social-post text when possible, instead of preserving short links or social wrapper URLs.

If metadata lookup fails, MailMoi falls back to the title, description, image, and URL captured from the shared item.

## Share Extension

The `MailMoiShare` extension is included for iPhone, iPad, and macOS share sheets.

- It accepts URL, text, image, HTML, and JavaScript-preprocessed share payloads from the host app.
- It reads the title, description, URL, and first shared image from the shared item when the host app provides them.
- For X/Twitter shares, it can rewrite noisy shared text into a cleaner draft and canonicalize tweet URLs before fetching preview metadata.
- If `Auto-send` is enabled and a default recipient is already saved, it waits 0.5 seconds after the draft is ready, then tries to send automatically.
- While auto-send is in progress, the sheet shows an `Auto-Sending...` state with a secondary `Edit` action that stays available during that 0.5-second grace period and still cancels the in-flight auto-send attempt without changing the saved `Auto-send` preference.
- If you tap `Send`, MailMoi first saves the draft to the queue, dismisses the sheet immediately, and then continues best-effort preview enrichment and delivery in the background. If that background work does not finish, the queued item is retried later.
- If `Auto-send` is disabled, it stays open and pre-fills the draft so you can review before sending.
- If immediate delivery fails, it writes the message into the shared queue and exits cleanly.
- If the host app only supplies a URL, the extension can still fetch metadata and allow manual editing before queueing.
- Image-only shares from apps like Photos are stored in the shared App Group container, then cleaned up after send or deletion.

## Distribution

The current build is set up to ship through TestFlight.

- Xcode Cloud is configured to start on pushes to `main`.
- The active workflow archives both iOS and macOS builds.
- Successful archives are prepared for `TestFlight (Internal Testing Only)`.
- The project keeps the branded `mail-moi.icon` file as the editable design source, while shipping builds use the checked-in `AppIcon.appiconset` so iPhone, iPad, and macOS all share the same explicit asset-catalog icon path.

That means a merge into `main` should automatically enqueue a new TestFlight build for the current internal testers.

Before each archive, you can run:

```sh
./scripts/prepare_release.sh --version 0.3
```

That command updates `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` across both targets, then prints the current signing team and bundle IDs so the release settings are easy to verify before uploading. If you only need the next build number, run `./scripts/prepare_release.sh` with no arguments.

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

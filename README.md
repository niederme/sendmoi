# SendMoi

SendMoi is a native SwiftUI app for iPhone, iPad, and macOS that turns shared links, posts, and photos into polished, responsive emails. It uses Gmail OAuth, keeps a durable offline queue, and includes a native Share Extension so shares from the system sheet do not get dropped.

The public marketing site for `send.moi` now lives in `docs/` inside this repo. Product-internal notes still live alongside it under `docs/superpowers` and `docs/content-copy-inventory.md`.

Project legal docs:

- Privacy Policy: [PRIVACY.md](/Users/niederme/~Repos/sendmoi/PRIVACY.md)
- Terms of Service: [TERMS.md](/Users/niederme/~Repos/sendmoi/TERMS.md)

## Current Status

SendMoi currently ships the full core workflow:

- Sign in with Gmail using OAuth 2.0 + PKCE.
- Send from the authenticated Gmail account.
- Save a default recipient in its own dedicated settings section and reuse recent recipients.
- Use the app to manage Gmail, recipient defaults, share-sheet behavior, a desktop compose guide panel, and the offline queue.
- Show a compact iPhone settings intro subhead under the main title and use roomier spacing between settings sections for readability.
- Handle links, pasted post text, and image-only shares as first-class queueable items.
- Queue every outbound email locally before network delivery.
- Retry queued emails when the app launches, becomes active, or connectivity returns.
- Detect missing Gmail send permission on queued delivery failures and prompt the user to reconnect Gmail before retrying.
- Share queue state, saved recipients, and session data through the App Group `group.com.niederme.mailmoi`.
- Let the share sheet either send immediately or stay open with a pre-filled draft, based on the global `Auto-send` setting in the app.
- Use the iOS `UILaunchScreen` asset configuration (`AppIconBackground` + `Splash`) directly at startup, without an extra in-app splash overlay.
- Use a settings-style form on iPhone and iPad, and a desktop card layout on macOS.
- Show the iPhone/iPad `Offline Queue` section as a collapsible row with queue-state summary text and a prominent `Send Queued Now` action in the expanded content.
- Show a branded first-run setup guide with step-by-step onboarding, Gmail connect/switch, and a final “ready” step that can save recipient defaults before entering settings.
- Keep the onboarding hero demo video fully silent without interrupting background audio from other apps.
- Let users reopen setup from the app and run a destructive reset flow that disconnects Gmail and clears saved setup preferences.

The app is built entirely with Apple-native frameworks, including `SwiftUI`, `AuthenticationServices`, `Network`, `Security`, and `FoundationModels` when available.

Deployment compatibility:

- iOS minimum deployment target is `18.0` for both `SendMoi` and `SendMoiShare`.
- Foundation Models summary generation is availability-gated and only runs on supported newer OS versions; older supported OS versions fall back to the built-in non-AI summarizer.

## What It Sends

Each email is sent through the Gmail API with a subject in this format:

```text
<article title> (Sent via SendMoi)
```

For reachable web URLs, SendMoi attempts to enrich the message before sending:

- Uses the page `<title>` when available, with sensible metadata fallbacks.
- Pulls a page description when one is available.
- Generates a short summary when enough high-quality body content is available (including concise profile/home pages), sizing the blurb to the amount of source text instead of always forcing an article-length recap.
- Keeps promo filtering strict for obvious CTA fragments while avoiding false positives that can drop substantive profile/homepage lines.
- Strips generic "here is a summary" lead-ins and markdown formatting artifacts from generated summaries, and suppresses summary output for structured listing pages (for example event schedules or real-estate listing blobs) when the content quality is low.
- Inlines a preview image when the page exposes one and the image fetch succeeds.
- Renders the HTML email as a responsive card layout for desktop and mobile clients.
- Normalizes common shared-post formats, including X/Twitter share text and Overcast titles, before building the email.
- Promotes real article URLs out of shared social-post text when possible, instead of preserving short links or social wrapper URLs.
- For X/Twitter shares, canonicalizes `.../video/1` or `.../photo/1` URLs back to the tweet status URL, and promotes `t.co` short links to the resolved status URL when possible so source links stay readable.

If metadata lookup fails, SendMoi falls back to the title, description, image, and URL captured from the shared item.

## Share Extension

The `SendMoiShare` extension is included for iPhone, iPad, and macOS share sheets.

- It accepts URL, text, image, HTML, and JavaScript-preprocessed share payloads from the host app.
- It reads the title, description, URL, and first shared image from the shared item when the host app provides them.
- For X/Twitter shares, it can rewrite noisy shared text into a cleaner draft and canonicalize tweet URLs before fetching preview metadata.
- If Gmail is not connected, the share sheet shows a `Connect Gmail in SendMoi` alert and can start the Google sign-in flow directly from the share sheet.
- If `Auto-send` is enabled and a default recipient is already saved, it waits 1 second after the draft is ready, then tries to send automatically.
- While auto-send is in progress, the sheet shows an `Auto-Sending...` state with a secondary `Edit` action that stays available during that 1-second grace period and still cancels the in-flight auto-send attempt without changing the saved `Auto-send` preference.
- If Gmail is not connected yet, automatic sending is held back so the share sheet does not imply that delivery is already underway.
- If you tap `Send`, SendMoi first saves the draft to the queue, dismisses the sheet immediately, and then continues best-effort preview enrichment and delivery in the background. If that background work does not finish, the queued item is retried later.
- If `Auto-send` is disabled, it stays open and pre-fills the draft so you can review before sending.
- If no default recipient is saved, the share sheet shows a neutral inline helper under `To`, then promotes that guidance into a red validation message only after you tap `Send` without a recipient; on iPhone and iPad it also returns focus to the `To` field so you can fix it immediately.
- If immediate delivery fails, it writes the message into the shared queue and exits cleanly.
- If the host app only supplies a URL, the extension can still fetch metadata and allow manual editing before queueing.
- If URL metadata for an X/Twitter share is missing a preview image, the share extension now tries a Link Presentation image fallback (including `t.co` and `pic.twitter.com` variants) and stores that image in the shared container for inline send.
- Image-only shares from apps like Photos are stored in the shared App Group container, then cleaned up after send or deletion.

## Distribution

The current build is set up to ship through TestFlight.

- Xcode Cloud is configured to start on pushes to `main`.
- The active workflow archives both iOS and macOS builds.
- Successful archives are prepared for `TestFlight (Internal Testing Only)`.
- `SendMoi/AppIcon.icon` is the single source of truth for the app icon. It is processed directly by actool (`folder.iconcomposer.icon`) alongside `Assets.xcassets`, so `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` resolves from the Icon Composer file without any exported PNG set. Do not revert to a PNG-based `AppIcon.appiconset` — the `.icon` file is the build source, not just an editable reference.

To update the artwork, open `SendMoi/AppIcon.icon` in Icon Composer, make changes, and commit. No PNG export or extra build steps are needed.

That means a merge into `main` should automatically enqueue a new TestFlight build for the current internal testers.

Before each archive, you can run:

```sh
./scripts/prepare_release.sh --version 0.4
```

That command updates `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` across both targets, then prints the current signing team and bundle IDs so the release settings are easy to verify before uploading. If you only need the next build number, run `./scripts/prepare_release.sh` with no arguments.

## Website Preview

The lightweight website for `send.moi` lives in `docs/`.

From the repo root:

```bash
make
```

That serves `docs/` on all interfaces, opens the site locally, and prints:

- a `.local` URL for this Mac
- a LAN URL for other devices on the same network

Default preview port is `8000`. If that port is already in use, `make dev` automatically picks the next available port.

Localhost-only preview:

```bash
make dev-local
```

Worktree-friendly preview:

```bash
make dev-thread
```

`make dev-thread` starts from `8001` so the main checkout can keep `8000`.

Project worktrees should live under repo-local `.worktrees/`.

### Live Reload

Use `make dev-live` for the standard live-reload preview. The underlying switch is `LIVE=1`, which is also available for the thread and local-only variants:

```bash
make dev-live
make dev-live-thread
make dev-local LIVE=1
```

Live reload watches:

- `docs/**/*.html`
- `docs/**/*.css`
- `docs/**/*.js`
- `docs/assets/**/*`

Requirements for live reload:

- Node.js with `npx` available
- a Node runtime that supports `node:path`
- recommended local version: Node 20

### Website Deploy

Pushing to `main` triggers the website deploy workflow automatically, and you can also run the same deploy manually with `workflow_dispatch` in GitHub Actions.

For manual or local deploys, use:

```bash
./scripts/deploy-site.sh
```

Preview only:

```bash
DRY_RUN=1 ./scripts/deploy-site.sh
```

Default deploy settings in [`scripts/deploy-site.sh`](scripts/deploy-site.sh):

- `DEPLOY_HOST=ssh.suckahs.org`
- `DEPLOY_USER=suckahs`
- `DEPLOY_PATH=/home/suckahs/public_html/sendmoi`
- `SITE_URL=https://send.moi`

Optional overrides:

- `DEPLOY_PORT`
- `DRY_RUN=1`
- `DEPLOY_IDENTITY_FILE`

GitHub Actions expects the repository secret `SSH_PRIVATE_KEY` to contain the deploy key for `suckahs@ssh.suckahs.org`.

## App Development

For local development builds:

1. Open [SendMoi.xcodeproj](/Users/niederme/~Repos/sendmoi/SendMoi.xcodeproj) in Xcode.
2. In `Signing & Capabilities`, enable `Automatically manage signing`.
3. Make sure both targets use the same Apple Developer team:
   - `SendMoi`
   - `SendMoiShare`
4. Confirm the App Group capability is enabled for both targets and matches `group.com.niederme.mailmoi`.
5. Run the shared `SendMoi` scheme on iPhone, iPad, or macOS.

The repo already includes a configured OAuth client ID in [GoogleOAuthConfig.swift](/Users/niederme/~Repos/sendmoi/SendMoi/Services/GoogleOAuthConfig.swift). If you are moving this project to a different Google Cloud project, update the client ID there and keep the redirect configuration aligned with [Info.plist](/Users/niederme/~Repos/sendmoi/SendMoi/Info.plist).

## Known Limitations

- Background delivery while the app is fully terminated is not implemented. The queue is durable, but retries resume only after the app launches, becomes active, or the share extension runs again.
- TestFlight distribution is currently configured for internal testing only.
- Bundle identifiers now use `com.niederme.SendMoi` and `com.niederme.SendMoi.ShareExtension`.
- Command-line builds require valid provisioning for `com.niederme.SendMoi` and `com.niederme.SendMoi.ShareExtension`. In Xcode, automatic signing handles this; with `xcodebuild`, use `-allowProvisioningUpdates`.

## License

MIT with [Commons Clause](https://commonsclause.com). Free to use, modify, and distribute - commercial or proprietary use is not permitted.

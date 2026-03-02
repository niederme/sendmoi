# MailMoi Handoff

Last updated: March 2, 2026

## Current State

- Repo: `main`
- Latest intended app version: `0.2`
- Recent shipped commits:
  - `334a80e` `Separate recipient settings from account`
  - `ecf4b78` `Add handoff notes and launch screen fix`
  - `1f7086d` `Bump version to 0.2`

## What Changed Recently

- Share-sheet behavior is now controlled by a global `Auto-send` setting in the main app instead of living inside the compose form.
- The default recipient is now a separate top-level `Recipient` section instead of being nested inside the collapsed `Account` view.
- The default recipient field now saves via the keyboard submit action (`Done`) and via an explicit prominent `Save Default Recipient` button that dismisses focus before saving.
- If `Auto-send` is off, the share extension stays open and pre-fills the draft rather than sending immediately.
- Compose UI was tightened:
  - recent recipients are helper chips under `To`
  - title is a 3-line field
  - description and summary loaders are shown only when useful
  - the primary action is a real button
- Email rendering was updated:
  - linked headline is no longer permanently underlined
  - summary preamble cleanup was added
  - preview image and summary handling were improved
- Added:
  - `PRIVACY.md`
  - iOS launch screen asset and storyboard (`Splash.imageset`, `LaunchScreen.storyboard`)
- `README.md` now reflects current behavior instead of hardcoding the old `0.1` release framing.
- New in the current working tree:
  - the macOS app now uses a desktop-style card layout instead of reusing the iPhone/iPad form
  - image-only shares are first-class queue items, with fallback titles like `Shared Photo`
  - share-extension media is persisted into the shared App Group container and deleted after send / queue deletion
  - the share extension activation rule now accepts image, text, URL, HTML, and property-list payloads
  - X/Twitter share text and Overcast links are normalized more aggressively before sending
  - shared X/Twitter links now prefer canonical tweet/content URLs, with an X oEmbed fallback for tweet previews when page metadata is weak
  - low-quality summaries are filtered more aggressively, and summaries are skipped for X/Twitter and Overcast sources
  - the app now uses a branded `mail-moi.icon` Icon Composer asset, with refreshed raster icons and updated bundle icon references
  - iOS startup now includes a short branded splash overlay in addition to the launch storyboard
  - the share extension processing state now says `Auto-Sending...` and exposes a small bordered `Edit` action that cancels auto-send and returns to the draft without changing the saved preference

## Things To Verify On The Next Machine

1. Open the project in Xcode and confirm the `LaunchScreen.storyboard` warning is gone after reloading the project / cleaning builds.
2. Confirm the new `Recipient` section placement feels right on iPhone, that `Account` now only handles Gmail sign-in state, and that the recipient save action dismisses the keyboard cleanly.
3. Do a true cold launch on iPhone after reinstalling the app to verify the splash screen appears (Apple caches launch screens aggressively).
4. Confirm App Store Connect metadata versions match the code version:
   - project is now `0.2`
   - App Store Connect screenshot previously showed macOS app version `1.0`
5. Share a photo directly from Photos (without a URL) and confirm it can be queued, sent, and removed without leaving orphaned files in the App Group container.
6. Share an X/Twitter post and an Overcast episode and confirm the title / source URL / summary behavior looks intentional rather than noisy.
7. Run the macOS target and confirm the desktop card layout feels right at common window sizes, especially queue deletion and account disclosure behavior.

## Local Setup

1. Open `MailMoi.xcodeproj` in Xcode.
2. Enable automatic signing for both `MailMoi` and `MailMoiShare`.
3. Confirm the App Group is `group.com.niederme.mailmoi`.
4. If moving to a different Google Cloud project, update `MailMoi/Services/GoogleOAuthConfig.swift`.

## Notes

- `build/` is intentionally ignored in `.gitignore` and should remain untracked build output only.
- Command-line builds in this environment were limited by provisioning / simulator / Xcode sandbox issues, so final verification should be done in Xcode.

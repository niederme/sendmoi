# MailMoi Handoff

Last updated: March 4, 2026

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
- The main app no longer exposes a manual compose section; drafting and editing now live only in the share sheet.
- The leftover manual-compose state was also removed from `AppModel`, so the main app no longer keeps its own unused draft metadata pipeline.
- Email rendering was updated:
  - linked headline is no longer permanently underlined
  - summary preamble cleanup was added
  - preview image and summary handling were improved
- Added:
  - `PRIVACY.md`
  - iOS launch screen asset and storyboard (`Splash.imageset`, `LaunchScreen.storyboard`)
- `README.md` now reflects current behavior instead of hardcoding the old `0.1` release framing.
- New in the current working tree:
  - `CURRENT_PROJECT_VERSION` is now `3` for both targets so the next Xcode Cloud upload does not reuse the already-uploaded bundle version `2`
  - the legacy `CFBundleIconFile` override was removed, and the main app now ships from the explicit `AppIcon.appiconset` while keeping `mail-moi.icon` as the editable design source
  - `scripts/prepare_release.sh` now bumps version/build across both targets and prints the signing + bundle settings before an archive
  - the macOS app now uses a desktop-style card layout instead of reusing the iPhone/iPad form
  - image-only shares are first-class queue items, with fallback titles like `Shared Photo`
  - share-extension media is persisted into the shared App Group container and deleted after send / queue deletion
  - the share extension activation rule now accepts image, text, URL, HTML, and property-list payloads
  - X/Twitter share text and Overcast links are normalized more aggressively before sending
  - shared X/Twitter links now prefer canonical tweet/content URLs, with an X oEmbed fallback for tweet previews when page metadata is weak
  - low-quality summaries are filtered more aggressively, and summaries are skipped for X/Twitter and Overcast sources
  - iOS startup now includes a short branded splash overlay in addition to the launch storyboard
  - the share extension processing state now says `Auto-Sending...`, keeps `Edit` available for a 0.5-second grace period before auto-send starts, and uses a roomier bordered `Edit` action that still cancels auto-send and returns to the draft without changing the saved preference
  - manual sends now queue first and dismiss the sheet immediately, then continue best-effort preview enrichment and delivery in the background; if that work does not finish, the queued item remains for later retry

## Things To Verify On The Next Machine

1. Open the project in Xcode and confirm the `LaunchScreen.storyboard` warning is gone after reloading the project / cleaning builds.
2. Confirm the new `Recipient` section placement feels right on iPhone, that `Account` now only handles Gmail sign-in state, that the recipient save action dismisses the keyboard cleanly, and that the manual compose section is gone from the main app.
3. Do a true cold launch on iPhone after reinstalling the app to verify the splash screen appears (Apple caches launch screens aggressively).
4. Confirm App Store Connect metadata versions match the code version:
   - project is now `0.2`
   - App Store Connect screenshot previously showed macOS app version `1.0`
5. Share a photo directly from Photos (without a URL) and confirm it can be queued, sent, and removed without leaving orphaned files in the App Group container.
6. Share an X/Twitter post and an Overcast episode and confirm the title / source URL / summary behavior looks intentional rather than noisy.
7. Run the macOS target and confirm the desktop card layout feels right at common window sizes, especially queue deletion and account disclosure behavior.
8. Run `./scripts/prepare_release.sh --version <next-version>` before the next archive, then verify App Store Connect accepts the `AppIcon` set for both iOS and macOS, shows the expected branded thumbnail, and no longer includes `mail-moi.icon` as an extra bundled resource.
9. Confirm the next Xcode Cloud upload succeeds with build number `3`; the previous failure was `The bundle version must be higher than the previously uploaded version.`

## Local Setup

1. Open `MailMoi.xcodeproj` in Xcode.
2. Enable automatic signing for both `MailMoi` and `MailMoiShare`.
3. Confirm the App Group is `group.com.niederme.mailmoi`.
4. If moving to a different Google Cloud project, update `MailMoi/Services/GoogleOAuthConfig.swift`.

## Notes

- `build/` is intentionally ignored in `.gitignore` and should remain untracked build output only.
- Command-line builds in this environment were limited by provisioning / simulator / Xcode sandbox issues, so final verification should be done in Xcode.

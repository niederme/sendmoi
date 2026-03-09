# SendMoi Handoff

Last updated: March 9, 2026

## Current State

- Repo: `codex/reel-visual-fallback`
- Latest intended app version: `0.3`
- Recent shipped commits:
  - `334a80e` `Separate recipient settings from account`
  - `ecf4b78` `Add handoff notes and launch screen fix`
  - `1f7086d` `Bump version to 0.2`
- GitHub state:
  - `main` includes `09eb66a` `Refine missing recipient validation in share sheet (#12)`
  - PR `#10` `Start Gmail sign-in directly from the share sheet` is merged and issue `#9` is closed
  - PR `#12` `Refine missing recipient validation in share sheet` is merged and issue `#11` is closed

## What Changed Recently

- Share-sheet behavior is now controlled by a global `Auto-send` setting in the main app instead of living inside the compose form.
- The default recipient is now a separate top-level `Recipient` section instead of being nested inside the collapsed `Account` view.
- The default recipient field now saves via the keyboard submit action (`Done`) and via an explicit prominent `Save Default Recipient` button that dismisses focus before saving.
- First-run now presents a branded 3-step setup guide as a modal instead of replacing the app shell, and setup can be reopened later from the dedicated bottom `Setup` actions.
- The onboarding finish step now shows the connected Gmail account, allows `Switch Account`, uses an explicit recipient `Save` action, and only reveals auto-send when a saved recipient is active.
- The onboarding action row was normalized so the primary action stays pinned and `View Settings` appears as a full-width secondary control on the final step.
- The share-extension `Auto-Sending...` overlay card now uses a softer translucent material treatment.
- The share-extension `Auto-Sending...` overlay now treats any tap on the dimmed screen as `Edit`, matching the explicit `Edit` button.
- If `Auto-send` is off, the share extension stays open and pre-fills the draft rather than sending immediately.
- The desktop app includes a compose card again; the missing `desktopComposeCard` helper was restored so the macOS workspace compiles, but the card is informational only and points users back to the share sheet for actual drafting.
- Email rendering was updated:
  - linked headline is no longer permanently underlined
  - summary preamble cleanup was added
  - preview image and summary handling were improved
  - summary length now scales with extracted page text length so shorter pages get shorter blurbs instead of forcing article-sized summaries
- Added:
  - `PRIVACY.md`
  - `TERMS.md`
  - iOS launch screen asset (`Splash.imageset`)
- `README.md` now reflects current behavior instead of hardcoding the old `0.1` release framing.
- New in the current working tree:
  - repo-wide rename from MailMoi to SendMoi: project, targets, schemes, folders, and user-facing copy
  - bundle identifiers, App Group ID, and shared container/keychain storage identifiers were migrated from the MailMoi namespace to SendMoi (`com.niederme.SendMoi*` and `group.com.niederme.sendmoi`), intentionally breaking in-place continuity with old installs
  - added a first-pass `TERMS.md` so the Google OAuth consent screen can point at a public Terms of Service URL alongside the existing privacy policy
  - `MARKETING_VERSION` is now `0.3` and `CURRENT_PROJECT_VERSION` is now `6` for both targets, set via `./scripts/prepare_release.sh --version 0.3`
  - the legacy `CFBundleIconFile` override was removed, and the main app now ships from the explicit `AppIcon.appiconset` while keeping `send-moi.icon` as the editable design source
  - `scripts/prepare_release.sh` now bumps version/build across both targets and prints the signing + bundle settings before an archive
  - the macOS app now uses a desktop-style card layout instead of reusing the iPhone/iPad form
  - image-only shares are first-class queue items, with fallback titles like `Shared Photo`
  - share-extension media is persisted into the shared App Group container and deleted after send / queue deletion
  - the share extension activation rule now accepts image, text, URL, HTML, and property-list payloads
  - X/Twitter share text and Overcast links are normalized more aggressively before sending
  - shared X/Twitter links now prefer canonical tweet/content URLs, with an X oEmbed fallback for tweet previews when page metadata is weak
  - low-quality summaries are filtered more aggressively, and summaries are skipped for X/Twitter and Overcast sources
  - `scripts/prune_app_icon_set.sh` now removes undeclared files from `AppIcon.appiconset` after icon refreshes so Xcode does not report `AppIcon` unassigned-child warnings from stray exported PNGs
  - the restored `desktopComposeCard` keeps the macOS compose panel buildable again after the helper was accidentally dropped from `ContentView.swift`, while preserving the current share-sheet-only drafting flow
  - iOS startup now uses `UILaunchScreen` (`AppIconBackground` + `Splash`) and no longer uses the old in-app `SplashOverlayView`
  - the share extension processing state now says `Auto-Sending...`, keeps `Edit` available for a 1-second grace period before auto-send starts, and uses a roomier bordered `Edit` action that still cancels auto-send and returns to the draft without changing the saved preference
  - manual sends now queue first and dismiss the sheet immediately, then continue best-effort preview enrichment and delivery in the background; if that work does not finish, the queued item remains for later retry
  - if no default recipient is saved, the share extension now starts with a neutral inline helper under `To`, only switches to the red validation copy after a failed send attempt, and refocuses the `To` field so the user can recover immediately
  - if Gmail is not connected, the share sheet now stops before auto-send, presents a `Connect Gmail in SendMoi` alert, and can start Google sign-in directly from the share sheet so queued items can resume sending with less ambiguity
- refreshed the SendMoi icon source in `marketing/send-moi.icon` and `SendMoi/send-moi.icon`, regenerated every `AppIcon.appiconset` size from the updated 1024 master PNG, and updated marketing icon exports in this repo
- share-sheet image handling now preserves multiple shared images, stores them in the queue schema, and renders them as multiple inline images in the outbound email instead of dropping everything after the first photo
- URL-only Instagram shares now try the post page's embedded `application/json` first and then fall back to the `/embed/captioned/` payload so carousel images use Instagram's uncropped display variants instead of the Open Graph thumbnail; the send path also prefers that richer metadata over the earlier single-image/single-excerpt fallback
- TikTok shares now parse poster/caption data from TikTok's structured page payload, and TikTok videos plus Instagram reels are clamped to a single poster image while Instagram photo galleries still render every shared image
- `Splash.imageset` now uses the latest `marketing/app-splash/SendMoi Splash.svg` artwork as a vector asset (`preserves-vector-representation = true`) and removes the legacy raster `splash.png` file

## Things To Verify On The Next Machine

1. Open the project in Xcode and confirm a cold launch shows the current `Splash` launch asset (not a stale cached launch snapshot).
2. Confirm the new `Recipient` section placement feels right on iPhone, that `Account` now only handles Gmail sign-in state, that the recipient save action dismisses the keyboard cleanly, and that the macOS desktop compose card appears without trying to edit main-app draft state.
3. Do a true cold launch on iPhone after reinstalling the app to verify the splash screen appears (Apple caches launch screens aggressively).
4. Confirm App Store Connect metadata versions match the code version:
   - project is now `0.3`
   - App Store Connect screenshot previously showed macOS app version `1.0`
5. Publish stable public URLs for both the privacy policy and terms page on `nieder.me`, then attach those URLs to the Google OAuth consent screen so the blue missing-policy banner disappears.
6. Share a photo directly from Photos (without a URL) and confirm it can be queued, sent, and removed without leaving orphaned files in the App Group container.
7. Share an X/Twitter post and an Overcast episode and confirm the title / source URL / summary behavior looks intentional rather than noisy.
8. Run the macOS target and confirm the desktop card layout feels right at common window sizes, especially queue deletion and account disclosure behavior.
9. Run `./scripts/prepare_release.sh --version <next-version>` before the next archive, then verify App Store Connect accepts the `AppIcon` set for both iOS and macOS, shows the expected branded thumbnail, and no longer includes `send-moi.icon` as an extra bundled resource.
10. Confirm the next Xcode Cloud upload succeeds with build number `3`; the previous failure was `The bundle version must be higher than the previously uploaded version.`
11. After the next icon refresh, run `./scripts/prune_app_icon_set.sh` and confirm Xcode no longer shows `AppIcon` asset warnings before archiving.
12. Re-share an Instagram carousel post from a build with the latest Gmail metadata changes and confirm the outbound email now includes the inline images plus the preview comment instead of falling back to the Open Graph-only excerpt.
13. Share a multi-photo Instagram or Photos gallery and confirm every attached image survives queueing, preview refresh, retry, and eventual cleanup.
14. Share an Instagram post from the app when only the URL is passed and confirm SendMoi still renders the carousel images and first preview comment from the fetched page payload.
15. Share a TikTok video and an Instagram reel and confirm the outbound email renders exactly one poster image instead of stacking alternate cover variants.
16. Launch the share sheet while signed out of Gmail and confirm the new connect alert appears, starts Google sign-in directly from the share sheet, and resumes without implying that auto-send already happened.
17. Open the share sheet with no default recipient and confirm the initial helper text feels neutral, then tap `Send` and verify the red validation state appears and the `To` field becomes focused.
18. Re-run Google Auth Platform branding verification using `https://send.moi/` as homepage and `https://send.moi/privacy/` + `https://send.moi/terms/` as policy links. The current rejection cites two issues from the previous attempt: no privacy-policy link on `https://nieder.me` and `https://send.moi/privacy/` flagged as a non-qualified policy domain.

## Local Setup

1. Open `SendMoi.xcodeproj` in Xcode.
2. Enable automatic signing for both `SendMoi` and `SendMoiShare`.
3. Confirm the App Group is `group.com.niederme.sendmoi`.
4. If moving to a different Google Cloud project, update `SendMoi/Services/GoogleOAuthConfig.swift`.

## Notes

- `build/` is intentionally ignored in `.gitignore` and should remain untracked build output only.
- Command-line builds in this environment were limited by provisioning / simulator / Xcode sandbox issues, so final verification should be done in Xcode.
- A full local build succeeded with: `xcodebuild -project SendMoi.xcodeproj -scheme SendMoi -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`.
- The local worktree on `codex/reel-visual-fallback` is currently mixed and not safe to commit wholesale: it contains icon pipeline changes, launch asset changes, identity/config updates, Gmail/share-sheet code changes that already landed on `main` via `#10` and `#12`, docs updates, and new untracked marketing/docs assets. Review and split intentionally before committing.
- This branch is currently `11` commits ahead of `origin/main`; before resuming on another machine, compare it against `main` and carve the remaining local-only work into smaller branches instead of reviving the whole mixed diff.

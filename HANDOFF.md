# SendMoi Handoff

Last updated: March 10, 2026

## Current State

- Repo: `codex/worktree-helpers` (based on `origin/main`)
- Latest intended app version: `0.3`
- Recent shipped commits:
  - `ec40844` `Use Icon Composer .icon file as app icon source, drop legacy PNG appiconset (#33)`
  - `0e5a871` `Fix summary promo filtering for concise homepage copy (#18)`
  - `0488709` `Allow summaries for concise high-quality pages (#16)`

## Quick Resume On Another Mac

1. `git clone https://github.com/niederme/sendmoi.git`
2. `cd sendmoi`
3. `git checkout codex/worktree-helpers`
4. `git pull --rebase origin main`
5. Open `SendMoi.xcodeproj` in Xcode and continue from `codex/worktree-helpers`.

## What Changed Recently

- Onboarding connected-account layout now preserves a one-line `Switch Account` button label by prioritizing button width and allowing the email/details text block to truncate first.
- `AGENTS.md` issue-media guidance no longer requires uploading screenshots/videos into the repo (for example `docs/bugs/...`); local-only media can be user-attached manually.
- Share-sheet behavior is now controlled by a global `Auto-send` setting in the main app instead of living inside the compose form.
- The default recipient is now a separate top-level `Recipient` section instead of being nested inside the collapsed `Account` view.
- The default recipient field now saves via the keyboard submit action (`Done`) and via an explicit prominent `Save Default Recipient` button that dismisses focus before saving.
- First-run now presents a branded 3-step setup guide as a modal instead of replacing the app shell, and setup can be reopened later from the dedicated bottom `Setup` actions.
- The onboarding finish step now shows the connected Gmail account, allows `Switch Account`, uses an explicit recipient `Save` action, and only reveals auto-send when a saved recipient is active.
- The onboarding action row was normalized so the primary action stays pinned and `View Settings` appears as a full-width secondary control on the final step.
- The `Clear Settings` reset confirmation now uses a standard alert so iPhone shows a visible `Cancel` action alongside the destructive button.
- The share-extension `Auto-Sending...` overlay card now uses a softer translucent material treatment.
- If `Auto-send` is off, the share extension stays open and pre-fills the draft rather than sending immediately.
- The desktop app includes a compose card again; the missing `desktopComposeCard` helper was restored so the macOS workspace compiles, but the card is informational only and points users back to the share sheet for actual drafting.
- Email rendering was updated:
  - linked headline is no longer permanently underlined
  - summary preamble cleanup was added
  - preview image and summary handling were improved
  - summary length now scales with extracted page text length so shorter pages get shorter blurbs instead of forcing article-sized summaries
  - summary generation now accepts concise but substantive pages (70+ cleaned words), so profile/home pages can still produce a 1-2 sentence recap
  - summary promo filtering now treats newsletter mentions as promo only for short CTA-style lines, so substantive profile/homepage content is not dropped from summary input
  - summary sanitization now strips generic lead-ins like "Here is a summary...", removes markdown formatting artifacts (for example `**bold**`), rejects affiliate-disclosure boilerplate, and suppresses low-signal structured listing summaries (for example Ticketmaster/Zillow-style schedule or listing blobs)
- Added:
  - `PRIVACY.md`
  - `TERMS.md`
  - iOS launch screen asset (`Splash.imageset`)
- `README.md` now reflects current behavior instead of hardcoding the old `0.1` release framing.
- `AGENTS.md` now treats `BUG:` and `ISSUE:` as the explicit GitHub issue creation prefixes.
- The onboarding footer now leaves `Skip` on its own and groups `Back` with the trailing primary action.
- Onboarding compact-layout detection is now device-based (not step-1-only), so step 2/3 typography, card spacing, and bottom inset scale correctly on smaller iPhones.
- Onboarding step 2 now adds `Step x of 3` progress text, tappable pagination dots, compact-phone image padding tuning, and explicit accessibility labels/hints for each slide.
- Onboarding step 3 now uses a clearly-disabled `chevron.right` trailing nav control when Gmail is disconnected, keeps `Connect Gmail` as the in-card primary action, and adds helper copy that clarifies users can still skip and connect later.
- The onboarding hero demo now builds a video-only playback item so it stays silent and no longer steals audio focus from background audio.
- iOS deployment target is now `18.0` for both `SendMoi` and `SendMoiShare`; Foundation Models summary support remains optional at runtime and falls back on unsupported OS versions.
- New in the current working tree:
  - repo-wide rename from MailMoi to SendMoi: project, targets, schemes, folders, and user-facing copy
  - bundle identifiers now match the renamed app targets: `com.niederme.SendMoi` and `com.niederme.SendMoi.ShareExtension`; shared App Group and storage identifiers remain on the existing MailMoi values for continuity
  - added a first-pass `TERMS.md` so the Google OAuth consent screen can point at a public Terms of Service URL alongside the existing privacy policy
  - `MARKETING_VERSION` is now `0.3` and `CURRENT_PROJECT_VERSION` is now `6` for both targets, set via `./scripts/prepare_release.sh --version 0.3`
  - the legacy `CFBundleIconFile` override was removed
  - `scripts/prepare_release.sh` now bumps version/build across both targets and prints the signing + bundle settings before an archive
  - the macOS app now uses a desktop-style card layout instead of reusing the iPhone/iPad form
  - image-only shares are first-class queue items, with fallback titles like `Shared Photo`
  - share-extension media is persisted into the shared App Group container and deleted after send / queue deletion
  - the share extension activation rule now accepts image, text, URL, HTML, and property-list payloads
  - X/Twitter share text and Overcast links are normalized more aggressively before sending
  - shared X/Twitter links now prefer canonical tweet/content URLs, including promotion away from `t.co` short links when the resolved status URL is available, with an X oEmbed fallback when page metadata is weak
  - when X/Twitter metadata does not provide a preview image, the share extension now attempts a Link Presentation image fallback (including `t.co` and `pic.twitter.com` links) and stores the result in the shared container for inline send
  - low-quality summaries are filtered more aggressively, and summaries are skipped for X/Twitter and Overcast sources
  - the restored `desktopComposeCard` keeps the macOS compose panel buildable again after the helper was accidentally dropped from `ContentView.swift`, while preserving the current share-sheet-only drafting flow
  - iOS startup now relies on `UILaunchScreen` in `Info.plist`; the extra in-app splash overlay was removed so the startup mark matches the launch asset instead of rendering an SF Symbol paper plane
  - the share extension processing state now says `Auto-Sending...`, keeps `Edit` available for a 1-second grace period before auto-send starts, and uses a roomier bordered `Edit` action that still cancels auto-send and returns to the draft without changing the saved preference
  - manual sends now queue first and dismiss the sheet immediately, then continue best-effort preview enrichment and delivery in the background; if that work does not finish, the queued item remains for later retry
  - if Gmail is not connected, the share sheet now stops before auto-send, presents a `Connect Gmail in SendMoi` alert, and can start Google sign-in directly from the share sheet so queued items can resume sending with less ambiguity
  - if no default recipient is saved, the share extension now starts with a neutral inline helper under `To`, only switches to the red validation copy after a failed send attempt, and refocuses the `To` field so the user can recover immediately
  - `SendMoi/AppIcon.icon` is now the direct build source for the app icon: actool processes it as `folder.iconcomposer.icon` alongside `Assets.xcassets`, so `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` resolves from the Icon Composer file without any exported PNG set — do not revert to a PNG-based `AppIcon.appiconset`; to update artwork, edit `AppIcon.icon` in Icon Composer and commit
  - added `./scripts/new-task` to create branch-scoped Git worktrees for parallel tasks (defaults to `codex/*` branch naming)
  - added `./scripts/close-task` to squash-merge task branches into `main` with cleanup for local worktrees/branches
  - added `.githooks/pre-commit` guard to block direct commits on `main` (after local `git config core.hooksPath .githooks`)

## Things To Verify On The Next Machine

1. Open the project in Xcode and confirm there are no asset catalog warnings and the app icon resolves correctly from `AppIcon.icon`.
2. Confirm the new `Recipient` section placement feels right on iPhone, that `Account` now only handles Gmail sign-in state, that the recipient save action dismisses the keyboard cleanly, and that the macOS desktop compose card appears without trying to edit main-app draft state.
3. Do a true cold launch on iPhone after reinstalling the app to verify the splash screen appears (Apple caches launch screens aggressively).
4. Confirm App Store Connect metadata versions match the code version:
   - project is now `0.3`
   - App Store Connect screenshot previously showed macOS app version `1.0`
5. Publish stable public URLs for both the privacy policy and terms page on `nieder.me`, then attach those URLs to the Google OAuth consent screen so the blue missing-policy banner disappears.
6. Share a photo directly from Photos (without a URL) and confirm it can be queued, sent, and removed without leaving orphaned files in the App Group container.
7. Share an X/Twitter post (including `t.co` and `/video/`/`/photo/` variants) and an Overcast episode and confirm title, source URL, summary, and preview image behavior all look intentional rather than noisy.
8. Run the macOS target and confirm the desktop card layout feels right at common window sizes, especially queue deletion and account disclosure behavior.
9. Run `./scripts/prepare_release.sh --version <next-version>` before the next archive, then verify App Store Connect accepts the `AppIcon` set for both iOS and macOS and shows the expected branded thumbnail.
10. Confirm the next Xcode Cloud upload succeeds with build number `3`; the previous failure was `The bundle version must be higher than the previously uploaded version.`
12. Launch the share sheet while signed out of Gmail and confirm the new connect alert appears, starts Google sign-in from the share sheet itself, and resumes sending without implying that auto-send already happened.
13. Open the share sheet with no default recipient and confirm the initial helper text feels neutral, then tap `Send` and verify the red validation state appears and the `To` field becomes focused.
14. Share a concise profile/homepage URL that includes a newsletter mention in body copy and confirm SendMoi still generates a short summary when the page has meaningful text.
15. Confirm App Store Connect processing reports iOS compatibility as `iOS 18.0 or later` after uploading the next archive.
16. Share a Zillow or Ticketmaster listing URL and confirm SendMoi omits low-quality structured summaries instead of sending scraped listing blobs, markdown artifacts, or generic "Here is a summary..." prefixes.

## Local Setup

1. Open `SendMoi.xcodeproj` in Xcode.
2. Enable automatic signing for both `SendMoi` and `SendMoiShare`.
3. Confirm the App Group is `group.com.niederme.mailmoi`.
4. Run `git config core.hooksPath .githooks` once so the main-branch commit guard is active.
5. If moving to a different Google Cloud project, update `SendMoi/Services/GoogleOAuthConfig.swift`.

## Notes

- `build/` is intentionally ignored in `.gitignore` and should remain untracked build output only.
- Command-line builds in this environment were limited by provisioning / simulator / Xcode sandbox issues, so final verification should be done in Xcode.

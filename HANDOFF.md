# MailMoi Handoff

Last updated: March 1, 2026

## Current State

- Repo: `main`
- Latest intended app version: `0.2`
- Recent shipped commits:
  - `1f7086d` `Bump version to 0.2`
  - `2064381` `Refine compose flow and share sheet behavior`
  - `494553f` `Fix README email wording`

## What Changed Recently

- Share-sheet behavior is now controlled by a global `Auto-send` setting in the main app instead of living inside the compose form.
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

## Uncommitted Change Included In This Handoff

- `MailMoi.xcodeproj/project.pbxproj` currently contains a launch-screen fix:
  - `LaunchScreen.storyboard in Resources` now has `platformFilter = ios;`
  - this is meant to stop Xcode from validating the iOS launch storyboard against the macOS side of the target

## Things To Verify On The Next Machine

1. Open the project in Xcode and confirm the `LaunchScreen.storyboard` warning is gone after reloading the project / cleaning builds.
2. Do a true cold launch on iPhone after reinstalling the app to verify the splash screen appears (Apple caches launch screens aggressively).
3. Confirm App Store Connect metadata versions match the code version:
   - project is now `0.2`
   - App Store Connect screenshot previously showed macOS app version `1.0`

## Local Setup

1. Open `MailMoi.xcodeproj` in Xcode.
2. Enable automatic signing for both `MailMoi` and `MailMoiShare`.
3. Confirm the App Group is `group.com.niederme.mailmoi`.
4. If moving to a different Google Cloud project, update `MailMoi/Services/GoogleOAuthConfig.swift`.

## Notes

- `build/` is intentionally ignored in `.gitignore` and should remain untracked build output only.
- Command-line builds in this environment were limited by provisioning / simulator / Xcode sandbox issues, so final verification should be done in Xcode.

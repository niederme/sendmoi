# SendMoi Content Inventory

Last updated: April 16, 2026

This is the working copy document for product messaging, in-app copy, and App Store Connect metadata.

## Current Source Of Truth

- There is no separate `Content Polish` brief in the repo today.
- Current app copy lives primarily in `SendMoi/ContentView.swift`, `SendMoiShare/ShareView.swift`, `SendMoi/AppModel.swift`, and `SendMoiShare/ShareExtensionModel.swift`.
- App Store Connect metadata is not currently versioned in this repo.
- Current working branch: `main`

## Positioning Snapshot

- App name: `SendMoi`
- Core product requirement: SendMoi requires a Gmail account to deliver email.
- Current in-app hero tagline: `Send Anything to Yourself`
- Current onboarding promise: `Share to SendMoi. It arrives as a polished email to yourself.`
- Current desktop hero line: `A macOS workspace for queueing shared links, refining drafts, and sending as soon as Gmail is available.`

## Tagline Notes

- `Send Anything to Yourself` is clear, but the product name already implies `send`, so the phrase feels slightly repetitive.
- `Email Anything to Yourself` is more literal, but less distinctive.
- The bigger issue is not just style. The top-line copy should state or strongly imply that Gmail is required, because that is not an optional integration.
- Strong working alternatives:
  - `Turn Anything Into a Gmail Draft`
  - `Send Yourself Anything with Gmail`
  - `Share Anything, Send with Gmail`
  - `Save Anything to Your Gmail Inbox`

## Messaging Constraint

- SendMoi is not a generic email client with optional provider support.
- Gmail OAuth is required for the sending flow.
- Users may be able to open the app or prepare a draft before connecting Gmail, but the app's core promise is blocked until Gmail is connected.
- That means the first screen, onboarding, and App Store subtitle should all make the Gmail dependency obvious.
- Current copy that may blur this:
  - `Skip if you want`
  - `You can use the app now and connect Gmail later.`
  - `Send Anything to Yourself`

## Messaging Direction

- Preferred framing: lead with the outcome, then name Gmail immediately.
- Good structure:
  - what it does: share links, notes, and photos to yourself
  - how it works: sends through Gmail
  - fallback behavior: queues offline until Gmail/network are available
- Example top-line directions:
  - `Send yourself anything through Gmail.`
  - `Turn shares into polished Gmail emails.`
  - `Share links, notes, and photos to yourself with Gmail.`
  - `A Gmail-powered inbox for everything you want to keep.`

## In-App Copy Inventory

## Onboarding And Main Hero

Source: `SendMoi/ContentView.swift`

Onboarding is now 2 steps. The dedicated pin step and dedicated analytics step have been removed.

- App title: `SendMoi`
- Step 1 (welcome) headline: `Send anything to your Gmail inbox, with just two taps.`
- Step 1 subheading: `SendMoi sends links to Gmail as rich email cards, so they're easy to find and act on later.`
- Step 2 (finish) signed-out headline: `Connect Gmail to finish setup.`
- Step 2 signed-out feature: `Secure sign-in`
- Step 2 signed-out detail: `Google handles the login. SendMoi never sees your password or inbox.`
- Step 2 signed-out feature: `Skip if you want`
- Step 2 signed-out detail: `You can use the app now and connect Gmail later.`
- Step 2 signed-out action: `Connect Gmail`
- Step 2 signed-out footnote: `Or tap Skip below and connect later from Account.`
- Step 2 signed-in headline: `Ready to go.`
- Step 2 signed-in body: `Gmail is connected. Add a default recipient now, or leave it blank and choose in the share sheet each time.`
- Connected account label: `Connected Gmail`
- Connected account helper: `You can switch accounts before finishing setup.`
- Recipient label: `Default recipient`
- Recipient placeholder: `Email address (optional)`
- Recipient action: `Save`
- Toggle title: `Auto-send when ready`
- Toggle helper: `Or leave this off and review the draft every time.`
- Analytics toggle title: `Share anonymous usage analytics`
- Analytics toggle detail: `Installs, active use, and setup completion only. No personal info.`
- Primary actions: `Connect Gmail`, `Done`
- Secondary actions: `Skip`, `Back`, `Switch Account`

## Main App Sections

Source: `SendMoi/ContentView.swift`

- Account section title: `Account`
- Signed-out state: `No Gmail account connected.`
- Sign-in action: `Sign In With Google`
- Sign-out action: `Sign Out`
- Account footer, iPhone/iPad: `Tap to manage Gmail sign-in.`
- Account footer, macOS: `Manage Gmail sign-in for the desktop app.`
- Recipient section title: `Recipient`
- Recipient field label: `Default Recipient`
- Recipient placeholder: `Email address`
- Recipient action: `Save Default Recipient`
- Recipient footer: `Used as the default when starting from the share sheet.`
- Share Sheet section title: `Share Sheet`
- Toggle title: `Auto-send`
- Auto-send on footer: `Items shared from other apps send automatically when enough details are available.`
- Auto-send off footer: `Items shared from other apps stay open so you can review the draft before sending.`
- Queue section title: `Offline Queue`
- Empty queue state: `No pending emails.`
- Queue action: `Send Queued Now`
- Setup section title: `Setup`
- Setup actions: `Open Setup Guide`, `How to Pin SendMoi`, `Clear Settings`
- Setup footer: `Open Setup Guide keeps your current account. How to Pin adds SendMoi to your share sheet. Clear Settings disconnects Gmail and resets SendMoi to first launch.`
- Attribution: `SendMoi by John Niedermeyer, with a little help from Codex, Claude Code and friends.`

## Desktop App Copy

Source: `SendMoi/ContentView.swift`

- Sidebar subtitle: `Desktop workspace`
- Sidebar section title: `Workspace`
- Status section title: `Live Status`
- Status labels: `Online`, `Offline`
- Status helper, empty queue: `Queue is clear`
- Status helper, non-empty queue: `Queued item(s) waiting`
- Overview intro: `A macOS workspace for queueing shared links, refining drafts, and sending as soon as Gmail is available.`
- Main actions: `Compose`, `View Queue`
- Preferences intro: `Set the default recipient and decide how shared items behave before they hit the queue.`
- Compose intro: `Build the draft, enrich it with preview data, and queue it for delivery.`
- Compose card subtitle: `Drafting and editing now happen in the share sheet.`
- Compose explainer: `SendMoi now treats the main app as a control center for account, defaults, and queue recovery. To create a new draft, share a link, note, or image from another app into SendMoi.`
- Compose how-to:
  - `Share content into SendMoi from Safari, Photos, or another app.`
  - `Edit the draft in the share sheet if Auto-send is off.`
  - `If sending cannot finish immediately, SendMoi keeps the item in the offline queue and retries later.`
- Queue intro: `Items wait here when Gmail is unavailable and send automatically once the app can reach the network.`
- Queue footer, empty: `Queue is empty.`

## Share Extension Copy

Source: `SendMoiShare/ShareView.swift`

- Navigation title: `SendMoi`
- Form section title: `Send Email`
- Field labels: `To`, `Title`, `Description`, `Link (Optional)`
- Recipient placeholder: `Email address`
- Link placeholder: `https://example.com`
- Multi-image helper: `N photos attached`
- AI section title: `AI Summary`
- Recent recipients label: `Recent`
- Toolbar actions: `Cancel`, `Send`, `Sending…`
- Auto-send footer: `SendMoi sends immediately when it can. If you're offline or Gmail is unavailable, it saves to the offline queue.`
- Manual-send footer: `SendMoi pre-fills these fields from the shared item and waits for you to tap Send. If you're offline or Gmail is unavailable, it saves to the offline queue.`
- Auto-send overlay action: `Edit`

## Status And Error Copy

Sources: `SendMoi/AppModel.swift`, `SendMoiShare/ShareExtensionModel.swift`, `SendMoi/Services/SharedContainer.swift`, `SendMoi/Services/GmailAPIClient.swift`

- App startup default: `Configure Google OAuth, sign in, then queue or send shared items.`
- Signed-in state: `Signed in as <email>.`
- Signed-out state: `Signed out. Queued items stay on disk until you send them.`
- Queue needs auth: `You have queued items. Sign in to Gmail to send them.`
- Queue success: `Sent "<title>" to <recipient>.`
- Queue retry failure: `Queued item kept for retry: <error>`
- Setup reset success: `Setup reset. Walk through the guide to reconnect Gmail and reconfigure defaults.`
- Share sheet loading: `Preparing your email...`
- Share sheet manual state: `Review and tap Send when ready.`
- Share sheet auto-send state: `Auto-Sending...`
- Share sheet preview wait: `Finishing preview before send...`
- Share sheet no content: `The share sheet did not provide anything to queue.`
- Share sheet extraction fallback: `Nothing was extracted automatically. You can still fill it in manually.`
- Missing recipient: `Enter a recipient in the To field, or set a default recipient in the SendMoi app.`
- Share item failure: `Could not send or save this share item: <error>`
- Rate limit error: `SendMoi send limit reached for this account. Try again in <time>.`
- Auth failure pattern: `Google sign-in failed: <reason>`

## App Store Connect Copy Tracker

Current status: not stored in repo yet.

Fields to capture and iterate here:

- App name
- Subtitle
- Promotional text
- Description
- Keywords
- What’s New
- Screenshot captions or screenshot callouts
- Privacy Policy URL
- Support URL
- Marketing URL

Current repo assets related to App Store presentation:

- iPhone screenshot: `marketing/app-store-screenshots/01-iOS.png`
- macOS screenshot: `marketing/app-store-screenshots/02-MacOS.png`
- iPad screenshot: `marketing/app-store-screenshots/03-iPad.png`

## Working Draft For App Store Connect

- App name: `SendMoi`
- Subtitle: `TBD`
- Promotional text: `TBD`
- Description: `TBD`
- Keywords: `TBD`
- What’s New: `TBD`
- Screenshot callouts: `TBD`

## Recommended Next Pass

- Pick a replacement for the hero tagline first, because it affects onboarding, screenshots, and App Store subtitle direction.
- Rewrite the first-screen and onboarding copy so Gmail is named immediately instead of appearing later as setup detail.
- Tighten the onboarding copy so it sounds less operational and more outcome-focused.
- Normalize `send`, `share`, `queue`, and `save` language so the product describes itself the same way across onboarding, settings, share sheet, and App Store copy.
- Draft App Store Connect metadata in this file before entering it manually in App Store Connect.

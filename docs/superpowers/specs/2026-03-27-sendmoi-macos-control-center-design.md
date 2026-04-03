# SendMoi macOS Control Center Redesign

## Goal

Redesign the macOS app so it feels like an honest desktop control center for SendMoi instead of a dashboard with several equal-weight panels. The new window should make it obvious whether SendMoi is ready, what is stuck in the queue, and what the user should do next.

## Problem

The current iOS share sheet is the clearest product surface in the app:

- it owns one job
- it shows the important fields inline
- it makes send, queue, and connection state explicit

The current macOS app is weaker because it spreads a small workflow across `Overview`, `Account`, `Preferences`, `Compose`, and `Queue` inside [ContentView.swift](/Users/niederme/~Repos/sendmoi/SendMoi/ContentView.swift). That creates three problems:

1. It implies capabilities that do not exist. The `Compose` panel is informational, not a true compose surface.
2. It gives tiny settings tasks the same visual weight as the queue, which is the real object users need to inspect and recover.
3. It keeps product state, layout state, onboarding, and styling in one very large file, which makes the UI harder to evolve coherently.

## Job To Be Done

When a user opens SendMoi on macOS, they are usually trying to answer one of these questions:

- Is SendMoi ready to receive shares?
- Is Gmail connected and healthy?
- Where will my shared items go?
- What is stuck, and how do I fix it?

The macOS app should optimize for those moments instead of acting like a desktop drafting app.

## Surface Model

### Primary Surface

`Queue`

This is the main object on desktop. It should occupy most of the window and own the primary actions:

- `Retry Now`
- `Reconnect Gmail`
- `Delete`

### Supporting Surface

`Setup`

This is a compact supporting area that shows and edits:

- Gmail account connection
- reconnect state
- default recipient
- auto-send preference
- reset and onboarding actions

### Ambient Signals

These should be visible without competing with the queue:

- online / offline
- connected account email
- reconnect required
- pending queue count

## What Is Working

- The share extension already has a focused, trustworthy interaction model.
- The app already treats onboarding as a modal flow instead of a separate first-run shell.
- Queue recovery, reconnect messaging, and auto-send state already exist in the model layer.
- The mac build is already shared SwiftUI code that ships to `macosx`, so the redesign can stay in one product codebase without switching architectures.

## What Is Weak Or Risky

- `Overview` is a dashboard-style summary without a strong action path.
- `Compose` is a false destination because drafting still happens in the share sheet.
- Separate full-screen `Account` and `Preferences` panels overstate the importance of small settings tasks.
- The top hero card is marketing-shaped, not task-shaped.
- [ContentView.swift](/Users/niederme/~Repos/sendmoi/SendMoi/ContentView.swift) is too large to be a stable home for the next round of desktop UI work.

## Recommended Change

Replace the current multi-panel macOS shell with a queue-first control center:

- Remove `Overview` as a destination.
- Remove `Compose` as a destination.
- Stop treating `Account`, `Preferences`, and `Queue` as peer screens.
- Make the window a two-column desktop surface:
  - dominant queue pane
  - compact setup sidebar / inspector
- Replace the hero card with a compact status header.

The new macOS window should feel closer to a recovery console or inbox utility than a dashboard.

## Window Structure

### Header

A compact header row, not a marketing hero.

Contents:

- app name
- connected Gmail account, or `Not Connected`
- online / offline badge
- queue count
- reconnect warning if required

This area should answer "is the system healthy?" in one glance.

### Main Queue Pane

The left or primary pane should own the queue.

Empty state:

- explain that new drafts come from the share sheet
- show that the queue is clear
- optionally offer `Open Setup Guide` if account or defaults are incomplete

Populated state:

- list queued items as rows or cards
- each row shows:
  - title
  - recipient
  - source host or URL
  - created time
  - last error when present
- row-level actions:
  - `Retry`
  - `Delete`
- top-level actions:
  - `Retry All`
  - `Reconnect Gmail` when required

Showing `created time` is a small net-new macOS UI addition. The data already exists on `QueuedEmail` as `createdAt`, but the current desktop UI does not surface it yet.

### Setup Sidebar

The secondary pane should hold compact cards:

1. `Gmail`
   - connected account
   - sign in / sign out
   - reconnect when scopes are stale
2. `Default Recipient`
   - current default
   - inline save
3. `Share Behavior`
   - auto-send toggle
   - short explanation
4. `Setup`
   - reopen onboarding
   - destructive reset

This keeps setup visible without letting it dominate the window.

## Onboarding Wizard

Keep the same logical flow as the existing onboarding, but present it as a mac-friendly modal setup wizard.

### Flow

1. `Welcome`
   - explain what SendMoi does on Mac
   - explain that sharing happens from other apps and the main app is the control center
2. `Connect Gmail`
   - authenticate the sending account
   - explain reconnect safety and queue behavior
3. `Choose Defaults`
   - save default recipient
   - decide whether auto-send should be enabled

### Step 1 Decision

The iOS onboarding step that teaches users to pin SendMoi in the share sheet does **not** carry over to macOS.

Do not try to translate that step literally.

On macOS, step 1 should become a real product-orientation step:

- what gets shared into SendMoi
- where drafting actually happens
- why the main app focuses on queue recovery and setup instead of composition

This preserves a 3-step wizard without inventing a fake Mac task.

### Behavior

- opens automatically on first launch
- reopens from setup actions
- reopens after destructive reset
- remains a modal sheet over the main control-center window

### State Ownership

The onboarding flow state should be shared, not duplicated per platform.

`OnboardingFlowView` should own the wizard state and pass bindings or explicit callbacks down into the mac and mobile onboarding views.

That shared state includes:

- current step
- recipient draft
- recipient confirmation state
- mobile-only pin-slide state
- transient onboarding presentation state such as the Gmail connect sheet

`MacOnboardingWizardView` and `MobileOnboardingView` should be presentational views over that shared flow state, not separate state machines.

### Mac Layout

The mac wizard should not reuse the tall mobile composition directly.

Use a wider layout:

- top progress / title area
- body split into explanation + form/action area
- bottom action bar with:
  - secondary action on the left
  - primary action on the right

The state machine and step meaning can stay shared, but the mac layout should feel like a setup wizard instead of a resized phone card.

### Wizard Columns

The body split should be explicit, not decorative.

#### Left Column: Context

This column explains the current step and gives confidence.

Step 1:

- simple `Share -> Queue -> Send` flow illustration
- short explanation of the mac role: control center, not compose surface
- examples such as Safari, Photos, or copied links

Step 2:

- trust and safety explanation
- Google handles sign-in
- queued items stay safe if offline or if Gmail is disconnected
- reconnect is possible later

Step 3:

- explanation of how default recipient and auto-send work together
- a small example of:
  - default recipient set + auto-send on
  - no default recipient or auto-send off

#### Right Column: Active Step

This column owns the actual interaction.

Step 1:

- headline and short body copy
- optional checklist or bullet list
- `Continue` as the main action

Step 2:

- connected account state or connect action
- `Connect Gmail` primary button
- fallback copy when OAuth is unavailable in development

Step 3:

- current connected account summary
- default recipient input
- auto-send toggle
- final completion action

## Governance And Trust

The redesign should keep trust-critical information close to the actions it affects:

- show the connected Gmail account near retry and reconnect controls
- show reconnect warnings near queue actions, not only in a generic status area
- show auto-send state near default recipient because those settings work together
- avoid ambiguous terms like `Compose` if composition cannot happen in the main app

## File Boundary Recommendation

Refactor the desktop UI before deeper visual changes.

Because this repo uses an explicit Xcode project file rather than automatic Swift package discovery, any new source files added under `SendMoi/Mac/` or `SendMoi/Onboarding/` must also be registered in [project.pbxproj](/Users/niederme/~Repos/sendmoi/SendMoi.xcodeproj/project.pbxproj) or added to the `SendMoi` target through Xcode. Creating files on disk alone will not make them part of the build.

Recommended boundaries:

- `SendMoi/ContentView.swift`
  - root platform switch only
- `SendMoi/Mac/MacControlCenterView.swift`
  - top-level mac window shell
- `SendMoi/Mac/MacQueuePane.swift`
  - queue list, empty states, retry actions
- `SendMoi/Mac/MacSetupSidebar.swift`
  - Gmail, recipient, auto-send, setup cards
- `SendMoi/Mac/MacStatusHeader.swift`
  - compact health/status row
- `SendMoi/Onboarding/OnboardingFlowView.swift`
  - shared onboarding flow orchestration and wizard state ownership
- `SendMoi/Onboarding/MacOnboardingWizardView.swift`
  - mac-specific onboarding layout
- `SendMoi/Onboarding/MobileOnboardingView.swift`
  - existing phone/tablet onboarding layout after extraction

The mac and mobile onboarding views should be mostly presentational and receive bindings or view-specific callbacks from that shared flow owner.

## Non-Goals

- Do not build a new desktop compose experience in this project.
- Do not move drafting out of the share sheet.
- Do not reuse the iOS "pin SendMoi in your Share Sheet" onboarding step on macOS.
- Do not redesign the share extension interaction model as part of this work.
- Do not rewrite the model layer unless a UI extraction exposes a small boundary issue that must be cleaned up.

## Success Criteria

The redesign is successful when:

- the macOS app has one obvious main surface
- the queue is the dominant object in the window
- users can see Gmail health and recovery actions without hunting
- onboarding still works as a modal wizard
- the UI code is split into smaller, focused files that are easier to evolve

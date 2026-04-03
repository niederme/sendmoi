# SendMoi macOS Control Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current multi-panel macOS shell with a queue-first control center and keep onboarding as a modal setup wizard with a mac-specific layout.

**Architecture:** Keep the shared SwiftUI app and model layer, but split the current monolithic `ContentView` into focused desktop and onboarding components. On macOS, make the queue the primary surface and move Gmail/defaults/setup into a compact supporting sidebar instead of separate full-window panels.

**Tech Stack:** SwiftUI, Observation via `ObservableObject`, Foundation, existing `AppModel`, existing Gmail/queue services, Xcode previews, `xcodebuild`

---

## File Structure

- Modify: `SendMoi/ContentView.swift`
  - reduce to root platform routing, modal presentation, and shared glue
- Modify: `SendMoi.xcodeproj/project.pbxproj`
  - add new source files to groups and the `SendMoi` target build phase
- Create: `SendMoi/Mac/MacControlCenterView.swift`
  - top-level mac window shell
- Create: `SendMoi/Mac/MacStatusHeader.swift`
  - compact account/network/queue header
- Create: `SendMoi/Mac/MacQueuePane.swift`
  - primary queue surface, empty state, row actions
- Create: `SendMoi/Mac/MacSetupSidebar.swift`
  - Gmail card, recipient card, auto-send card, setup card
- Create: `SendMoi/Onboarding/OnboardingFlowView.swift`
  - shared onboarding flow orchestration extracted from `ContentView`
- Create: `SendMoi/Onboarding/MacOnboardingWizardView.swift`
  - mac-specific wizard layout
- Create: `SendMoi/Onboarding/MobileOnboardingView.swift`
  - existing mobile/tablet onboarding layout after extraction

## Task 1: Extract The macOS Shell Boundary

**Files:**
- Modify: `SendMoi/ContentView.swift`
- Modify: `SendMoi.xcodeproj/project.pbxproj`
- Create: `SendMoi/Mac/MacControlCenterView.swift`

- [ ] **Step 1: Write the failing compile target by moving the macOS root out of `ContentView`**

Add the new shell entry point:

```swift
// SendMoi/Mac/MacControlCenterView.swift
import SwiftUI

struct MacControlCenterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Text("TODO: Mac control center")
    }
}
```

- [ ] **Step 2: Update `ContentView` to route desktop builds into the extracted shell**

Target shape:

```swift
@ViewBuilder
private var rootContent: some View {
    if usesDesktopLayout {
        MacControlCenterView()
    } else {
        mobileContent
    }
}
```

- [ ] **Step 3: Register the new source file in the Xcode project**

Because this repo uses explicit source-file entries in `SendMoi.xcodeproj/project.pbxproj`, adding a `.swift` file on disk is not enough.

Add:

- a `PBXFileReference`
- a `PBXBuildFile`
- the file under the `SendMoi` group or a new `Mac` subgroup
- the build file to the `SendMoi` `Sources` phase

If using Xcode instead of manual project editing, verify the file is added to the `SendMoi` target before continuing.

- [ ] **Step 4: Run build to verify the extraction compiles before deeper edits**

Run:

```bash
xcodebuild -scheme SendMoi -project SendMoi.xcodeproj -destination 'platform=macOS' build
```

Expected:

```text
BUILD SUCCEEDED
```

- [ ] **Step 5: Commit**

```bash
git add SendMoi/ContentView.swift SendMoi/Mac/MacControlCenterView.swift
git commit -m "refactor: extract mac control center shell"
```

## Task 2: Replace Desktop Destinations With A Queue-First Layout

**Files:**
- Modify: `SendMoi/ContentView.swift`
- Modify: `SendMoi.xcodeproj/project.pbxproj`
- Modify: `SendMoi/Mac/MacControlCenterView.swift`
- Create: `SendMoi/Mac/MacStatusHeader.swift`
- Create: `SendMoi/Mac/MacQueuePane.swift`
- Create: `SendMoi/Mac/MacSetupSidebar.swift`

- [ ] **Step 1: Remove the legacy desktop destination model**

Delete the current `DesktopPanel` enum and any selection state that only exists to switch between `Overview`, `Account`, `Preferences`, `Compose`, and `Queue`.

Expected simplified state in `ContentView`:

```swift
@State private var showsResetConfirmation = false
@State private var showsOnboardingAccountSheet = false
```

- [ ] **Step 2: Build the mac shell as one split layout**

Target structure:

```swift
// SendMoi/Mac/MacControlCenterView.swift
import SwiftUI

struct MacControlCenterView: View {
    @EnvironmentObject private var model: AppModel
    let openSetupGuide: () -> Void
    let showResetConfirmation: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MacStatusHeader()
            HSplitView {
                MacQueuePane()
                MacSetupSidebar(
                    openSetupGuide: openSetupGuide,
                    showResetConfirmation: showResetConfirmation
                )
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 360)
            }
        }
    }
}
```

- [ ] **Step 3: Implement the compact status header**

Header responsibilities:

- app name
- current Gmail identity or disconnected state
- online/offline badge
- queue count
- reconnect warning when needed

Minimal shape:

```swift
struct MacStatusHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Text("SendMoi")
                .font(.title3.weight(.semibold))
            Spacer()
            Text(model.session?.emailAddress ?? "Not Connected")
            Text(model.isOnline ? "Online" : "Offline")
            Text("\(model.queuedEmails.count) queued")
        }
        .padding(16)
    }
}
```

- [ ] **Step 4: Implement the queue pane as the dominant surface**

Queue pane responsibilities:

- empty state when queue is clear
- row list for queued items
- row-level delete / retry affordances
- top-level `Retry All`
- top-level `Reconnect Gmail` when required

This is not a pure extraction. The current desktop queue UI does not show `item.createdAt`, so surfacing created time here is a small net-new behavior that should be implemented deliberately.

Minimal row shape:

```swift
struct MacQueueRow: View {
    let item: QueuedEmail

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title).font(.headline)
            Text(item.toEmail).foregroundStyle(.secondary)
            Text(item.urlString).font(.footnote).foregroundStyle(.secondary)
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let lastError = item.lastError {
                Text(lastError).font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(14)
    }
}
```

- [ ] **Step 5: Implement the setup sidebar as compact cards**

Cards:

- `Gmail`
- `Default Recipient`
- `Share Behavior`
- `Setup`

The sidebar must reuse existing model actions instead of inventing new desktop-only state.

- [ ] **Step 6: Register the new mac source files in the Xcode project**

Update `SendMoi.xcodeproj/project.pbxproj` for:

- `SendMoi/Mac/MacStatusHeader.swift`
- `SendMoi/Mac/MacQueuePane.swift`
- `SendMoi/Mac/MacSetupSidebar.swift`

Required project updates:

- create file references
- create build file entries
- add them to a `Mac` group under `SendMoi`
- add them to the `SendMoi` target `Sources` phase

- [ ] **Step 7: Run build and verify the old fake surfaces are gone**

Run:

```bash
xcodebuild -scheme SendMoi -project SendMoi.xcodeproj -destination 'platform=macOS' build
```

Expected:

```text
BUILD SUCCEEDED
```

- [ ] **Step 8: Commit**

```bash
git add SendMoi/ContentView.swift SendMoi/Mac/MacControlCenterView.swift SendMoi/Mac/MacStatusHeader.swift SendMoi/Mac/MacQueuePane.swift SendMoi/Mac/MacSetupSidebar.swift
git commit -m "feat: replace mac dashboard with queue-first control center"
```

## Task 3: Extract Shared Onboarding Flow From `ContentView`

**Files:**
- Modify: `SendMoi/ContentView.swift`
- Modify: `SendMoi.xcodeproj/project.pbxproj`
- Create: `SendMoi/Onboarding/OnboardingFlowView.swift`
- Create: `SendMoi/Onboarding/MobileOnboardingView.swift`
- Create: `SendMoi/Onboarding/MacOnboardingWizardView.swift`

- [ ] **Step 1: Move onboarding orchestration into its own root view**

Extract the current onboarding state and actions into a dedicated wrapper:

```swift
// SendMoi/Onboarding/OnboardingFlowView.swift
import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var model: AppModel
    let isDesktopLayout: Bool
    let finish: () -> Void
    @State private var onboardingStep = 0
    @State private var onboardingRecipientDraft = ""
    @State private var onboardingRecipientConfirmed = false
    @State private var onboardingPulse = false
    @State private var onboardingPinSlide = 0
    @State private var showsOnboardingAccountSheet = false

    var body: some View {
        Group {
            if isDesktopLayout {
                MacOnboardingWizardView(
                    onboardingStep: $onboardingStep,
                    onboardingRecipientDraft: $onboardingRecipientDraft,
                    onboardingRecipientConfirmed: $onboardingRecipientConfirmed,
                    showsAccountSheet: $showsOnboardingAccountSheet,
                    finish: finish
                )
            } else {
                MobileOnboardingView(
                    onboardingStep: $onboardingStep,
                    onboardingRecipientDraft: $onboardingRecipientDraft,
                    onboardingRecipientConfirmed: $onboardingRecipientConfirmed,
                    onboardingPulse: $onboardingPulse,
                    onboardingPinSlide: $onboardingPinSlide,
                    showsAccountSheet: $showsOnboardingAccountSheet,
                    finish: finish
                )
            }
        }
    }
}
```

- [ ] **Step 2: Replace inline onboarding sheet content in `ContentView`**

Target shape:

```swift
.sheet(isPresented: $model.shouldShowOnboarding, onDismiss: finalizeOnboardingSheetState) {
    OnboardingFlowView(
        isDesktopLayout: usesDesktopLayout,
        finish: finalizeOnboardingSheetState
    )
    .environmentObject(model)
}
```

- [ ] **Step 3: Move onboarding state ownership into `OnboardingFlowView`**

State that currently lives in `ContentView` should move into the extracted flow owner:

- `onboardingStep`
- `onboardingRecipientDraft`
- `onboardingRecipientConfirmed`
- `onboardingPulse`
- `onboardingPinSlide`
- `showsOnboardingAccountSheet`

`ContentView` should stop owning that state after extraction.

The extracted mobile and mac onboarding views should receive bindings, a small coordinator object, or explicit callbacks from `OnboardingFlowView` rather than duplicating state.
For this plan, prefer bindings and explicit callbacks over introducing a new coordinator type.

- [ ] **Step 4: Keep the existing mobile/tablet onboarding behavior intact**

Move the current branded/tall layout into `MobileOnboardingView` with no intentional product changes.

- [ ] **Step 5: Define the mac onboarding step model explicitly**

The mac wizard must not reuse the mobile "pin SendMoi in your Share Sheet" step.

Use this 3-step desktop flow:

1. `How SendMoi works on Mac`
2. `Connect Gmail`
3. `Choose defaults`

Do not create a 2-step wizard unless the approved spec is changed again.

- [ ] **Step 6: Register the new onboarding source files in the Xcode project**

Update `SendMoi.xcodeproj/project.pbxproj` for:

- `SendMoi/Onboarding/OnboardingFlowView.swift`
- `SendMoi/Onboarding/MobileOnboardingView.swift`
- `SendMoi/Onboarding/MacOnboardingWizardView.swift`

Required project updates:

- create file references
- create build file entries
- add them to an `Onboarding` group under `SendMoi`
- add them to the `SendMoi` target `Sources` phase

- [ ] **Step 7: Run both macOS and iOS simulator builds to catch extraction regressions**

Run:

```bash
xcodebuild -scheme SendMoi -project SendMoi.xcodeproj -destination 'platform=macOS' build
xcodebuild -scheme SendMoi -project SendMoi.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected:

```text
BUILD SUCCEEDED
```

- [ ] **Step 8: Commit**

```bash
git add SendMoi/ContentView.swift SendMoi/Onboarding/OnboardingFlowView.swift SendMoi/Onboarding/MobileOnboardingView.swift SendMoi/Onboarding/MacOnboardingWizardView.swift
git commit -m "refactor: extract shared onboarding flow"
```

## Task 4: Build The macOS Modal Setup Wizard

**Files:**
- Modify: `SendMoi/Onboarding/MacOnboardingWizardView.swift`
- Modify: `SendMoi/ContentView.swift`

- [ ] **Step 1: Implement a mac-specific wizard layout for the existing 3-step flow**

Target structure:

```swift
struct MacOnboardingWizardView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var onboardingStep: Int
    @Binding var onboardingRecipientDraft: String
    @Binding var onboardingRecipientConfirmed: Bool
    @Binding var showsAccountSheet: Bool

    var body: some View {
        VStack(spacing: 0) {
            wizardHeader
            Divider()
            HSplitView {
                wizardContextColumn
                wizardStepColumn
            }
            Divider()
            wizardActionBar
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}
```

- [ ] **Step 2: Keep the same step meanings**

Do not invent a desktop-only onboarding flow. Preserve:

1. how SendMoi works on Mac
2. Gmail sign-in
3. default recipient + auto-send decision

- [ ] **Step 3: Implement the wizard columns with explicit responsibility**

Left column by step:

- step 1: `Share -> Queue -> Send` explainer and supported-source examples
- step 2: trust, privacy, and queue-safety explanation
- step 3: how recipient defaults and auto-send affect behavior

Right column by step:

- step 1: welcome headline, concise explanation, continue action
- step 2: connect Gmail action or connected-account state
- step 3: recipient input, auto-send toggle, completion action

- [ ] **Step 4: Reuse the existing `OnboardingGmailSheet` integration**

The auth handoff should still use the existing sign-in sheet behavior instead of introducing another sign-in path.

- [ ] **Step 5: Keep the wizard modal over the control-center window**

Do not move onboarding into a separate window or scene.

- [ ] **Step 6: Run build**

Run:

```bash
xcodebuild -scheme SendMoi -project SendMoi.xcodeproj -destination 'platform=macOS' build
```

Expected:

```text
BUILD SUCCEEDED
```

- [ ] **Step 7: Commit**

```bash
git add SendMoi/Onboarding/MacOnboardingWizardView.swift SendMoi/ContentView.swift
git commit -m "feat: add mac onboarding setup wizard"
```

## Task 5: Add Preview Coverage For Critical macOS States

**Files:**
- Modify: `SendMoi/Mac/MacControlCenterView.swift`
- Modify: `SendMoi/Mac/MacQueuePane.swift`
- Modify: `SendMoi/Mac/MacSetupSidebar.swift`
- Modify: `SendMoi/Onboarding/MacOnboardingWizardView.swift`

- [ ] **Step 1: Add preview fixtures for key control-center states**

Required preview states:

- empty queue + connected Gmail
- populated queue + online
- reconnect required
- signed out

Minimal preview helper:

```swift
@MainActor
private func previewModel() -> AppModel {
    let model = AppModel()
    model.defaultRecipient = "me@example.com"
    model.shareSheetAutoSendEnabled = true
    return model
}
```

- [ ] **Step 2: Add preview fixtures for onboarding**

Required preview states:

- welcome step
- Gmail connection step
- defaults step

- [ ] **Step 3: Build once more after previews**

Run:

```bash
xcodebuild -scheme SendMoi -project SendMoi.xcodeproj -destination 'platform=macOS' build
```

Expected:

```text
BUILD SUCCEEDED
```

- [ ] **Step 4: Commit**

```bash
git add SendMoi/Mac/MacControlCenterView.swift SendMoi/Mac/MacQueuePane.swift SendMoi/Mac/MacSetupSidebar.swift SendMoi/Onboarding/MacOnboardingWizardView.swift
git commit -m "test: add mac ui preview coverage"
```

## Task 6: Manual Verification

**Files:**
- Verify only

- [ ] **Step 1: Launch the macOS app from Xcode**

Manual checks:

- first launch shows modal onboarding wizard
- wizard layout feels desktop-native, not phone-stretched
- closing and reopening setup works from the sidebar

- [ ] **Step 2: Verify queue-first hierarchy**

Manual checks:

- queue is the first thing your eye lands on
- setup cards feel secondary but reachable
- there is no fake desktop compose surface

- [ ] **Step 3: Verify Gmail and recovery states**

Manual checks:

- signed out state is obvious
- reconnect state is obvious
- retry and reconnect actions are visible near queue actions

- [ ] **Step 4: Verify iPhone/iPad did not regress**

Manual checks:

- onboarding still appears correctly on iPhone
- current settings form still works
- queue disclosure section still behaves correctly

- [ ] **Step 5: Record any copy or hierarchy issues before polish work**

Write down:

- confusing labels
- weak empty-state copy
- spacing issues
- any remaining dashboard-like elements

## Task 7: Documentation Reconciliation

**Files:**
- Modify: `README.md`
- Modify: `HANDOFF.md`
- Modify: `docs/content-copy-inventory.md`

- [ ] **Step 1: Update README to reflect the new macOS control-center model**

Change references that describe:

- a desktop card layout with multiple panels
- a desktop compose guide panel

- [ ] **Step 2: Update HANDOFF with the redesign and verification notes**

Include:

- queue-first mac shell
- modal mac setup wizard
- removed fake compose surface

- [ ] **Step 3: Update content inventory copy**

Remove or replace copy for:

- old overview intro
- old compose intro
- old desktop hero line

- [ ] **Step 4: Commit**

```bash
git add README.md HANDOFF.md docs/content-copy-inventory.md
git commit -m "docs: update mac control center documentation"
```

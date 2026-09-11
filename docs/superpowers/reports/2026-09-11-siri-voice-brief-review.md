# Review: Use SendMoi through Siri

Date: September 11, 2026

Review of [Use SendMoi through Siri](../plans/2026-09-11-sendmoi-by-voice.md). Verdict: **endorsed.** The reframe is correct, step 1 is executable today with no new code, and the hardware blocker is resolved. Below: what was verified against the pushed branch, what will make the device test fail for non-platform reasons, and two decisions worth pre-committing before the test rather than after.

## 1. The reframe is right, and it should not drift back

SendMoi exists *because* Shortcuts-based Apple Mail scripting failed. The prior roadmap drifted into treating a Shortcuts release as a legitimate fallback outcome, which inverts the product's reason for existing. That row should stay deleted.

The technical distinction the brief draws is the load-bearing one: `AppShortcutsProvider` donates spoken phrases with **zero user configuration**. The user never opens the Shortcuts app. Shortcuts remains useful only as a *diagnostic* — a way to invoke an intent by hand to isolate whether the action itself works — and a manual tap never satisfies a voice milestone. The brief already says this; keep it.

Also correct: the mail-domain scope finding applies to that specific integration route, not to voice support generally.

## 2. Verified against `SendMoi/Probe/SiriProbe.swift`

Checked directly, since step 1 assumes a registered spoken phrase and nothing in the prior handoff confirmed one existed:

- **`AppShortcutsProvider` exists** in `SendMoi/Probe/SiriProbe.swift`, with `"Check \(.applicationName) connection"` and `"Preview this with \(.applicationName)"`. Step 1 is executable as written. No new feature code is needed — matching the brief's claim.
- **The installed phrase uses the probe's name, not the product's.** `SendMoi/Probe/Probe-Info.plist` sets `CFBundleDisplayName` to `SendMoi Probe` (wired via `INFOPLIST_FILE` in the SiriProbe configuration), so `\(.applicationName)` resolves to **"SendMoi Probe"**. The utterances are *"Check SendMoi Probe connection"* and *"Preview this with SendMoi Probe"*. Consequence: a pass proves **routing**, not phrase ergonomics — the production phrase stays unvalidated until the shipping app declares its own shortcuts, and a three-token app name is a harder matching target than the real one will be. Read the phrase off the Shortcuts entry rather than assuming it.
- Both intents declare `openAppWhenRun: false` and `supportedModes: .background` (availability-gated to iOS/macOS 26). The control intent `SendMoiConnectionCheck` is parameter-free and returns fixed text with no networking.

## 3. Device test: hardware is available; here is what will produce false failures

Target device: iPhone Air, iOS 27. Pairs with the Xcode 27 SDK the probe already builds against.

- **Signing.** The probe needs real provisioning for `com.niederme.SendMoi.SiriProbe` and `com.niederme.SendMoi.SiriProbe.ShareExtension` — two bundle IDs that likely have no App IDs registered yet. Use the Xcode GUI with automatic signing, which registers them. The README's CLI commands use `CODE_SIGNING_ALLOWED=NO` and will not work for device. This also requires finally clearing the outstanding "Install Required" system-components prompt.
- **Launch the app once after install.** App Shortcuts are not donated until the app has run at least once. This is the most common cause of a correctly-declared phrase doing nothing, and it is indistinguishable from a platform failure if not ruled out.
- **Confirm donation before speaking.** Open the Shortcuts app and verify **Check Connection** and **Preview Article** appear under SendMoi. This separates "not donated" from "donated but the phrase will not route" — different problems, not distinguishable from a failed voice attempt alone. It is a precondition check, not the voice milestone.
- **Do not uninstall production SendMoi.** Production's `AppShortcutsProvider` is inside `#if SENDMOI_SIRI_PROBE`, so it donates nothing, and the probe's distinct display name means there is no name collision either. Leave the daily driver installed.
- **Resolve the DDI first.** Xcode currently reports the iPhone as connected with no Developer Disk Image mounted. Device preparation has to complete before anything installs; this is the concrete form of the outstanding "Install Required" prompt.
- **Device language must be English**, since the phrases are English-only literals.
- Step 1 pass condition: say "Hey Siri, check SendMoi Probe connection" — or whatever phrase the Shortcuts entry actually shows. Record Siri's response **verbatim** and whether the app foregrounded. With `.background` and `openAppWhenRun: false` it should not foreground; if it does, that answers the background-execution question early and for free.

## 4. Step 2 is where this most likely ends — pre-commit to the decision now

**This section is a prediction, not a finding.** I know of no documented mechanism by which a custom App Intent with a `URL` parameter receives Safari's current page, so I expect Siri to prompt for the URL. That is an argument from absence of documentation — it is not derived from the mail-domain contract, and an earlier draft of this review overstated it as though it were. Apple documents some onscreen-context capability outside the assistant schemas; whether any of it reaches a third-party intent from Safari is unresolved either way. The device test decides it.

What *is* worth deciding in advance, because it is a product judgment rather than a technical one: **if Siri cannot resolve "this," there is probably no narrower version worth building.** Voice plus a dictated URL is worse than the share sheet. Voice-triggered sending of a previously shared article adds steps rather than removing them. The share extension already captures richer content (selected text, `og:` metadata, X post text) than any URL-only path can. A clean defer beats a diminished feature — and pre-committing keeps that call from being made under sunk cost.

Run step 2 in the same device session as step 1. Bound it in advance so it is neither over-iterated nor under-tested: **2–3 pre-chosen phrasings × 2–3 public articles**, recording for each what Siri heard, which URL arrived, whether it asked for clarification, and whether SendMoi came to the foreground.

**Safari must stay onscreen throughout.** Foregrounding SendMoi removes the article from the screen and changes what "this" can refer to, so foreground-vs-background is not a valid axis here. The state that varies is SendMoi's, with Safari in front the whole time: **backgrounded, and fully terminated**. (Foreground/background/terminated remains a fair matrix for the step 1 connection control, which takes no onscreen context.) If SendMoi foregrounds on its own during an attempt, that is itself a finding — it means the action did not run in background mode, and it displaced the very content under test.

That is a fair test. Hunting for a magic phrase beyond the fixed set is not — but neither is calling it impossible after one attempt.

## 5. Carry-forward decisions that should not be re-litigated

When step 3's implementation spec is written, these were settled earlier at some cost:

- **Uncertain delivery** resolves via the existing Offline Queue UI with an explicit manual send-again / discard choice. No automatic retry. **No new Gmail scopes** — reading back sent mail requires `gmail.readonly` or `gmail.metadata`, both restricted scopes requiring a third-party security assessment, a privacy-policy revision, and forced re-consent for every existing user. The current grant is `gmail.send`, `email`, `openid`.
- **An expired delivery claim transitions to `deliveryUncertain`, never back to `queued`** — otherwise the duplicate-send hazard is rebuilt with more machinery around it.
- **Siri confirmation is independent of `shareSheetAutoSendEnabled`.** The intent ignores that preference entirely.
- Timing budgets come from observed iPhone behavior, **not** from the share extension's 8s delivery watchdog or its 5s appex summary deadline. Those are share-sheet UX choices with no bearing on App Intent execution allowances.

## 6. Two small checks

- **Verify `supportedModes: 1` actually encodes background.** Generated metadata shows the raw bitmask. Flip the source to `.foreground`, rebuild, diff the value. Two minutes, and it matters for "can it run without opening the app."
- **Challenge-page rejection on `codex/enrichment-quality` is separately shippable.** There is no bot-challenge detection anywhere in `main`, and `shouldApplyPreviewTitle` returns `true` whenever the existing title is empty — the non-Safari share case — with the excerpt filled from the fetched description under the same condition. A challenge page's title and description can therefore reach a real email today. That guard is narrow and does not depend on the paragraph-preference or sidebar-stripping heuristics that still need X/social, selected-text, list-format and non-Safari regression coverage. It should not wait on the rest of that branch, and it is not a prerequisite for voice routing.

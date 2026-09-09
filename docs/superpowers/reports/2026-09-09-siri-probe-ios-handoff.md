# Probe split and iOS handoff

Date: September 9, 2026

## Decision and scope

Keep the full mail-schema adoption deferred on its contract/scope finding. Extraction quality does not change that finding. A narrower custom App Intent is a separate product option, still awaiting execution and physical-iPhone evidence. The macOS observations do not establish an iOS failure or a universal platform defect.

Production enrichment QA now has its own branch: `codex/enrichment-quality`, commit `f72e6dd`, worktree `.worktrees/enrichment-quality`, based directly on main at `663bd36`. It includes the extraction/fallback candidate and standalone checks, with no Siri configuration or warning copy. Its plan names X/social, selected-text, list/mixed-format, non-Safari, and real share-path regression coverage as merge prerequisites. Those broader tests are not yet implemented; this is a reviewable candidate, not a shipping fix.

The shared extraction policy changes have been removed from the current `codex/siri-probe` tip without rewriting its historical commits. The probe now measures the original production enrichment policy plus development-only instrumentation and budget controls. Past v3 metrics are historical and must not be represented as measurements of this new source. No branch was merged or pushed.

The limited-preview warning was already inside `#if SENDMOI_SIRI_PROBE`. It remains there. It is absent from the separate enrichment candidate and the built normal iOS binary; no real-email copy decision has been made.

## Instrumentation

`ProbePreview.metrics`, `ArticleResult.urlOnlyMetrics`, and `ArticleResult.browserContextMetrics` carry:

- `summarySource`: `model`, `extractive`, or `none`, recorded when output passes the applicable checks.
- `summaryPath`: `body` or `excerpt`, when a summary is selected.
- `budgetSeconds`: 8, and `modelBudgetSeconds`: 3.
- `phaseSeconds`: `fetch`, `extract`, `model`, and `image` wall durations.
- `recoveredBodyWords` and `wordClampApplied` for body selection and observed short-text clamping.

The per-invocation trace is locked and freezes on success or timeout. Failed harness cases retain partial timing evidence; late work cannot rewrite a completed record. Phase values measure instrumented operations, not an exhaustive CPU profile; some orchestration, fallback checks and final rendering lie outside these spans, and nested operations can overlap. `wordClampApplied` records observed short-text clamping in the pipeline, not proof that the selected summary is the clamped value. These limitations avoid pretending the added fields answer causality without inspecting them.

The probe gives all model attempts one cumulative three-second allowance, further reduced by remaining time. It retains the eight-second enrichment race and caps each optional image request at two seconds or the remaining time minus 250ms, whichever is smaller. Missing images still count as image-gate misses. Swift scheduling and framework cancellation are not hard real-time guarantees; the final rendering/return overhead also needs measurement before claiming an eight-second end-to-end guarantee. Production's existing share/app budgets are unchanged.

A single Mac command-line instrumentation smoke check using the fixed WebKit Grid Inspector URL returned `summarySource: extractive`, `summaryPath: body`, 718 recovered body words, and nonzero fetch/extract/model/image spans. It exercised the serializer and attribution, not Siri or a new corpus gate. The observed model span was about 3.19 seconds despite a three-second allowance, reinforcing the distinction between a requested deadline and wall-time guarantees. No new full corpus run was performed.

## iOS evidence

Target: iPhone 17 Pro simulator, iOS 27.0, UDID `BA998B86-058B-4144-ABEE-CEFE4D6391A2`.

- Instrumented `SendMoiProbe` builds, installs and launches.
- iOS Shortcuts launches and displays **Preview Article** and **Check Connection** under SendMoi Probe. A screenshot verified discovery.
- Generated iOS action metadata includes both intents, `openAppWhenRun: false`, and `supportedModes: 1`. The source explicitly specifies `.background`; the availability-gated property is present in this build's metadata.
- **Check SendMoi Connection** is a permanent development-only, parameter-free control that returns fixed text with no networking, enrichment, queue or Gmail access.
- Execution is **not yet verified**. The installed Xcode uses Device Hub; attempts to access its device UI through the available computer-use interface timed out. A `shortcuts://run-shortcut?name=Check%20Connection` attempt reported that no user shortcut of that name existed. That name-based URL attempt did not invoke the donated app action and is not evidence of an App Intent execution failure. The error was cleared by restarting simulator Shortcuts.
- No physical iPhone was available in `devicectl`. Simulator discovery does not verify Siri AI, on-screen URL resolution, or device model availability.

## macOS investigation closed for now

No further Launch Services or background-mode experiments were performed. The later -1712/no-invocation case provides no reason to pursue abandoned enrichment tasks for that specific attempt; it does not retroactively identify the cause of the earlier post-perform hang.

While preparing the iOS handoff, Xcode showed the duplicate Mac probe paused by its debugger at SIGTERM. The earlier signal had not actually stopped that debug session, so the previous report's description of fully stopping the duplicate was too strong. The debug session was then stopped with Xcode's Stop control. No macOS workflow rerun or causal conclusion followed. The old “Install Required” prompt was no longer visible, but no installation was performed in this work.

## Next manual test

Open the probe worktree's Xcode project and select **SendMoiProbe** with an iPhone destination. In iOS Shortcuts, tap the donated **Check Connection** action, or add **Check SendMoi Connection** to a new shortcut followed by Show Result. Confirm the exact fixed text: “SendMoi probe connected. Nothing sent or queued.” Repeat with the probe in the background and terminated. Then test **Preview with SendMoi** with the fixed WebKit Grid Inspector URL and verify returned preview text. Record foregrounding separately from returned output.

Only after those checks should a compatible physical iPhone test Siri against an article open in Safari. Do not equate explicit URL input with successful “this” resolution.

Reproducible build:

```sh
cd /Users/niederme/~Repos/sendmoi/.worktrees/siri-probe
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project SendMoi.xcodeproj -scheme SendMoiProbe -configuration SiriProbe \
  -destination 'platform=iOS Simulator,id=BA998B86-058B-4144-ABEE-CEFE4D6391A2' \
  -derivedDataPath build/probe-ios CODE_SIGNING_ALLOWED=NO build
```

Validation: probe checks pass (input, no-send, cancellation, partial timing and frozen evidence); probe and normal iOS builds pass. The independent enrichment checks and its normal iOS build pass. No full share-path or Xcode test target coverage is claimed.

# Siri probe follow-up

Date: September 9, 2026

## Decision

Continue to hold the sending phase. Shared extraction is improved, but the unchanged ten-URL corpus still fails the agreed gate and macOS Shortcuts completion remains blocked. No physical-iPhone or conversational Siri result is claimed.

## Changes

- Prefer substantive article sections over surrounding page chrome. Where at least 70 words of paragraph text exist, use that prose instead of headings and navigation lists.
- Strip sidebars, figures/captions, preformatted code blocks and other non-body elements. Remove explicit press-contact and editor-note lines.
- Extract text before invoking HTML entity decoding, avoiding full-page HTML layout and image loading during summary extraction. Skip the entity importer for text without ampersands.
- Use extractive fallback when a model response fails output checks. Excerpt fallback no longer starts a second model deadline. Enforce the word limit even for an overlong first sentence.
- Reject recognized challenge-page titles. Preserve supplied share context when available; do not attempt to bypass site challenges.
- Show an explicit limited-preview warning in the probe UI, HTML and returned text when no summary is available.

The shared changes affect normal preview/enrichment behavior when merged. They are still on the experiment branch. Paragraph preference can omit useful list-based material on mixed-format pages; regex extraction is not a full HTML parser. The current corpus does not cover every supported share format, so broader share-path regression review remains necessary before shipping.

## Unchanged corpus results

Original evidence remains in `build/siri-probe-fidelity/`. Intermediate extraction results are in `build/siri-probe-fidelity-v2/`; the final run is in `build/siri-probe-fidelity-v3/`. Compact metrics are committed alongside this report. Full HTML and source extracts remain ignored local artifacts.

| Case | Final URL-only result | Seconds |
| --- | --- | --- |
| NASA Webb | Summary and image; no credits/TOC, but summary ends mid-sentence | 6.79 |
| NASA Moon | Summary and image; navigation/object character removed | 5.60 |
| NPS trees | Summary and image | 4.08 |
| NPS leaves | Summary and image | 4.01 |
| Smithsonian light | Summary and image; press-contact boilerplate removed | 5.93 |
| Smithsonian cephalopods | Overall deadline exceeded | 8-second limit |
| WebKit Grid Inspector | Summary and image | 5.19 |
| WebKit Grid Lanes | Summary and image; largely extractive opening copy | 6.12 |
| Mozilla cookies | Limited preview, challenge title rejected, no summary | 0.26 |
| Mozilla FAQ | Limited preview, challenge title rejected, no summary | 0.06 |

Seven results contain summaries, versus five originally. This is not an 8/10 fidelity pass: one result is clipped, one article times out, and two are blocked. Five of five designated image cases now produce inline images, but actual Safari-attachment parity remains unverified. The timed-out article also prevents the 10/10 completed source-URL gate.

The intermediate run completed both previously timed-out articles; the final run timed out on cephalopods again. Do not claim that latency is fixed. These were single runs with nondeterministic model output and some concurrent local build activity, not a controlled performance benchmark. Both extraction and model timing need more margin.

## Shortcuts investigation

The original workflow again exceeded a 25-second CLI timeout. Logs showed Shortcuts invoking another Xcode-derived build with the same probe bundle ID, rather than the active worktree binary. The extra preview process was stopped, its duplicate Launch Services registration removed, and the signed worktree app registered and restarted.

A temporary constant-string action was compiled as a control. The first control attempt was invalid because logs proved the older real action was invoked instead. Later isolated attempts did not show action invocation and either timed out or returned OSStatus -1712. Therefore the control does **not** establish whether enrichment is responsible for the original completion failure.

The real action source and signed binary were restored. A fresh workflow, **SendMoi Preview Isolation**, was created with the same explicit WebKit Grid Inspector URL. It returned OSStatus -1712 after approximately 2.2 seconds, with no new perform invocation in the inspected app logs. The original workflow remains available. No daemon reset, system settings change, app deletion, or Gmail action was performed.

The remaining local blocker is action discovery/routing or workflow execution after duplicate development installations. Its exact cause is not established, and this result should not be described as a confirmed Apple platform defect. A clean runtime session and a verified constant-result control are the next platform checks, before returning to full enrichment and physical-iPhone Siri testing.

## Validation

- Deterministic checks pass: substantive article versus long sidebar; caption/resource/code/editor-note exclusion; HTML entities; summary word bound; positive and negative challenge-title cases; invalid URLs; disabled sending; cancellation.
- Normal Release and SiriProbe builds pass for macOS and iOS Simulator.
- Final signed macOS probe passes deep/strict signature verification.
- `git diff --check` passes.
- No queue changes, OAuth changes, delivery coordinator, or sending intent were added.

Build and harness commands remain in `scripts/siri-probe/README.md`. The most useful next content fixes are sentence-complete fallback and a bounded enrichment budget with room for image fetching. Preserve the corpus and report failures rather than substituting easier URLs.

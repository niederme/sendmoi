> **Historical report.** Its findings are retained; its next-step instructions are superseded by [Use SendMoi through Siri](../plans/2026-09-11-sendmoi-by-voice.md), September 11, 2026.

# Siri probe follow-up

Date: September 9, 2026

Later revision: [branch split, instrumentation, and iOS handoff](2026-09-09-siri-probe-ios-handoff.md). The extraction results below describe the pre-split experiment, not the current probe source.

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

| Case | Final URL-only result | Summary words | Seconds |
| --- | --- | --- | --- |
| NASA Webb | No credits/TOC, but clipped mid-sentence; not a clean pass | 100 | 6.79 |
| NASA Moon | Navigation/object character removed; source-grounded prose | 82 | 5.60 |
| NPS trees | Brief summary of winter adaptation; omits other major sections | 30 | 4.08 |
| NPS leaves | Brief source-grounded explanation of pigment changes; coverage needs review | 25 | 4.01 |
| Smithsonian light | Press-contact boilerplate removed; source-grounded prose | 88 | 5.93 |
| Smithsonian cephalopods | Overall deadline exceeded | 0 | 8-second limit |
| WebKit Grid Inspector | Source-grounded summary and image | 50 | 5.19 |
| WebKit Grid Lanes | Largely extractive opening copy; not established as a substantive pass | 89 | 6.12 |
| Mozilla cookies | Limited preview, challenge title rejected | 0 | 0.26 |
| Mozilla FAQ | Limited preview, challenge title rejected | 0 | 0.06 |

**The demonstrated improvement is reduced contamination, not a demonstrated increase in substantive passes.** Seven non-empty summaries versus five originally is an output-availability count, not the 8/10 product score. A consistent source-coverage review has not been completed across both runs, so neither a higher substantive score nor an exact unchanged 3/10 score is established. The gate still fails even before resolving the disputed cases.

Output length alone does not establish recovered source length or quality. The model path enforces its source-dependent minimum, but extractive fallback can return shorter text; the excerpt path is another possibility. The run did not record which path produced each result. In these saved NPS results, the summaries contain article-specific details absent from the recorded excerpts: cell sugar/dehydration for trees, and carotene for leaves. The leaves excerpt is only the title and cannot meet the excerpt fallback's 20-word minimum. Therefore these cases must not be described as confirmed description-only summaries. Their coverage should be judged against the saved article baselines, not a new 300-word minimum that was never part of the gate.

NASA Webb ends at the 100-word ceiling. Both the extractive summarizer and model-output postprocessing can clamp at that ceiling; sentence-incomplete word clamping is the immediate issue to fix. There is no evidence attributing it to the 180-token generation cap, and the producing path was not logged.

Five of five designated image cases produce inline images, but actual Safari-attachment parity remains unverified. The timed-out article prevents the 10/10 completed source-URL gate.

## Timing interpretation and next-run budget

Removing the second model deadline closes a concrete budget defect: two successive five-second model attempts could consume ten seconds inside an eight-second total budget. This is a plausible contributor to the original NASA Webb timeout, but the original run has no phase timings to establish that it took this path. Likewise, the remaining cephalopods timeout cannot yet be classified as a different root cause. Fetching, extraction, model work, and image loading remain candidates.

The intermediate run completed both previously timed-out articles; the final run timed out on cephalopods again. The seven completed article summaries averaged approximately 5.39 seconds; the slowest took 6.79 seconds, leaving 1.21 seconds (15%) of the total budget. This demonstrates inadequate evidence of reliable latency, not that every individual case is equally close to failure. These were single runs with nondeterministic model output and some concurrent local build activity, not a controlled performance benchmark.

Before another corpus run, adopt an explicit **eight-second total preview target with a maximum three-second model allowance**, further limited by the remaining total budget. This is a deliberate product experiment target for a responsive preview, not a claimed App Intents platform limit. Keep the total target unchanged so a longer wait cannot masquerade as improved fidelity. The app's production 12-second model allowance is a separate policy; it does not justify putting a 12-second model attempt inside this experiment's eight-second wall. The current committed probe still uses five seconds for the model: the three-second policy is the next implementation, not a completed change.

Instrument phase durations (page fetch, extraction, model, image fetch), recovered body-word count, summary origin (model/body extraction/excerpt), and truncation. Preserve partial timing evidence when the outer deadline fires. Share one remaining-time budget across phases, leave time for rendering, and return a clearly identified text-only preview when image work cannot fit. Treat such image omissions as image-gate misses. Implement sentence-complete fallback before rerunning the unchanged corpus; report any shorter-summary tradeoff explicitly. These measurements will distinguish extraction quality, model fallback, and network jitter.

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

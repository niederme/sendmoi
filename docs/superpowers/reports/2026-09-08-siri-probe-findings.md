# SendMoi non-sending Siri/Shortcuts probe

Date: September 8, 2026

Follow-up: [September 9 extraction fixes and rerun](2026-09-09-siri-probe-follow-up.md).

## Recommendation

Keep the custom preview action as an experiment. Do not proceed to the sending-intent or delivery-coordinator phase yet: the first URL-only fidelity run fails the agreed gate, and Apple's full mail-schema contract is substantially broader than SendMoi's current product.

This work implements the platform check, reusable preview seam, first content comparison, and development-only custom App Intent. It does not establish conversational Siri support or fix production delivery defects.

## Platform finding

[Apple's current mail-domain documentation](https://developer.apple.com/documentation/appintents/app-schema-domain-mail) requires all 12 listed actions when adopting any one: create/update/save/open/delete/send draft, plus open/reply/forward/update/archive/delete mail. It says Xcode validates the group at build time. Implementing fake or permanently unavailable mail actions would not be a sound production integration.

The installed Xcode 27 SDK declares the core mail schema symbols at iOS 18/macOS 15, `supportedModes` at iOS/macOS 26, and mail `openDraft`/`openMessage` at iOS/macOS 27. The probe compiles at the existing iOS 18/macOS 15 floors and gates the newer execution-mode property. It adopts no mail schema. A full mail-domain implementation/validation was deliberately stopped at the documented contract, not attempted as a larger mail-client build.

The custom action lives in the app target, accepts a URL, returns preview text, and requests background execution. Its generated metadata contains `PreviewWithSendMoi`, `openAppWhenRun: false`, and no assistant schemas. This establishes registration and compilation, not natural-language routing.

## What was built

- **SendMoiProbe scheme / SiriProbe configuration:** separate app identity, no shared-container entitlements or OAuth callback, preview-only launch path, inert share extension, and a compile-time disabled Gmail send method. Normal builds do not include the action or probe UI.
- **Preview UI and action:** use the existing content builder and HTML renderer. The preview embeds downloaded image data locally and applies an eight-second overall budget and five-second summary budget. No authentication, recipient selection, queue writes, analytics, or Gmail calls occur in this path.
- **Fidelity harness:** freezes ten URLs across five parent domains, compares URL-only output with rendered-page context, and writes local HTML/JSON evidence under ignored `build/`.
- **Checks:** invalid URL rejection, disabled sending, and cancellation propagation. These are probe checks, not delivery-safety tests.

The production metadata cache is bypassed in the probe so a prior preview cannot mask latency. The existing summarizer and fallback logic are otherwise retained. Model availability does not prove that a particular result came from the model.

## First frozen-sample run

Environment: macOS 27.0 (26A5425a), Xcode 27.0 (27A5194q), Apple Silicon. The model reported available in completed URL-only previews. Corpus: `scripts/siri-probe/corpus.json`. Each case ran once, URL-only first. This is a feasibility sample, not a reliability estimate or a representative consumer-content benchmark.

| Case | URL-only result | Elapsed | Assessment |
| --- | --- | --- | --- |
| NASA Webb | Budget exceeded | 8s limit | No completed preview |
| NASA Moon formation | Preview, image, summary | 5.83s | Summary includes navigation headings and an object-replacement character |
| NPS trees in fall | Preview, image, summary | 7.94s | Substantive summary; almost no timing margin |
| NPS changing leaves | Preview, image, summary | 5.10s | Substantive summary |
| Smithsonian bioluminescence | Preview, image, summary | 6.74s | Summary includes image credits and press-contact boilerplate |
| Smithsonian cephalopods | Budget exceeded | 8s limit | No completed preview |
| WebKit Grid Inspector | Preview, image, summary | 5.75s | Substantive summary |
| WebKit Grid Lanes | Preview and image | 6.29s | No summary |
| Mozilla cookie protection | Challenge-page title | 0.18s | Wrong content; no summary |
| Mozilla cookie FAQ | Challenge-page title | 0.07s | Wrong content; no summary |

**The 8/10 title-and-summary gate fails.** Only five URL-only results even contain a summary; three of those are clean substantive summaries in this run. Eight requests return a preview object, but that includes two bot-challenge pages. A successful return must not be equated with usable content.

Four of the five designated image cases produced an inline image. This is only an image-metadata proxy: the harness baseline does not capture actual Safari share attachments, so the formal Safari image-parity gate remains unverified. Two timed-out cases also prevent the complete 10/10 source-URL gate from passing.

All ten pages loaded in the unauthenticated WebKit baseline. The Mozilla pages had valid article titles/descriptions there while the native URL fetch received challenges. Supplying browser context recovers those fields but does not provide a summary. Some browser-context summaries also contain boilerplate, showing that not every failure is specific to Siri or URL-only input. Do not infer causation from a single order-dependent, nondeterministic model run.

## Verification and remaining limits

- Probe builds: macOS and iOS Simulator pass.
- Normal Release builds: macOS and iOS Simulator pass.
- Signed Mac probe: builds and passes signature verification, with sandbox/network entitlements and no App Group entitlement.
- iOS 18.1 simulator: probe installs and launches; screenshot inspected. This verifies an older supported runtime launch, not Siri AI.
- Mac UI: a NASA preview renders through the existing HTML template.
- Probe checks pass: invalid input, disabled send, cancellation.
- Shortcuts discovers the custom action. After replacing the unsigned process with the signed build, system logs confirm URL resolution, invocation, and return from `perform()` in approximately 6.5–7.3 seconds. However, the Shortcuts workflow did not finish or export its result during the first checks, including a simplified text-only return. Invocation is verified; end-to-end workflow completion is not yet a pass. A final fresh CLI run also exceeded a 25-second workflow timeout after the action returned. The cause has not been isolated; no Shortcuts end-to-end pass is claimed.
- Xcode GUI opens to an “Install Required” system-components prompt. CLI builds succeeded; that installation was not performed. GUI Run testing needs that local setup completed.
- Physical-iPhone Siri AI, automatic “this” resolution, and its foreground/background/terminated matrix remain unverified. No available physical iPhone was listed during this session. The paired iPad was not used as a substitute for the planned iPhone test.
- Actual Safari share attachments, selected-text/social/paywall diagnostics, and a representative broader article sample remain follow-up work. The initial gate already failed; no easier URLs were substituted.

## Next decision

First decide whether a narrower custom Shortcuts action is worth pursuing. Before calling it polished or reliable, address challenge-page detection, boilerplate filtering/fallback quality, and the latency budget, then rerun the unchanged sample. Keep physical-device Siri testing separate from explicit-URL Shortcuts success. The unrelated queue-concurrency defects remain worth fixing, but this experiment does not justify putting that refactor on the Siri critical path yet.

Run instructions and exact build commands: `scripts/siri-probe/README.md`.

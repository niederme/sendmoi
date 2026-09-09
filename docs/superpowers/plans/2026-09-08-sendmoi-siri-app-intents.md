# Preparing SendMoi for Siri AI and App Intents

Date: September 8, 2026

Status: Non-sending prototype implemented. Initial fidelity gate failed; sending phases have not started. See [probe findings](../reports/2026-09-08-siri-probe-findings.md).

## Why this work

The purpose of this work is to prepare SendMoi for Siri AI and determine how App Intents can make its core sharing workflow available through Siri and Shortcuts.

Apple's Siri AI integration gives apps a way to expose their content and actions so the system can understand requests, move content between apps, and perform tasks. App Intents is the integration foundation; compatible app schemas describe actions in a form Siri understands. SendMoi needs to explicitly adopt these interfaces to participate. Its existing AI summaries and share extension do not provide that integration on their own. See [Apple's developer overview](https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai).

For SendMoi, the opportunity is to let someone viewing an article ask Siri to send it through SendMoi, using our recipient defaults and polished email output. This could make SendMoi useful at the moment someone finds something worth sharing, without requiring them to navigate the share sheet.

We should investigate this now so our product and architecture are ready to support that entry point. Start with a lightweight platform check, a content-fidelity comparison, and a non-sending Siri probe. Address existing delivery hazards only before adding a sending intent. Then prototype Shortcuts and Siri, evaluate the evidence, write the production spec, and implement and validate the selected feature.

## Decision

Build a narrow prototype before writing a production feature spec. First check whether URL-only input preserves sufficient value and establish a tested delivery foundation. Then prove that Siri can obtain the intended content, invoke SendMoi, and produce an accurate delivery result. Use the evidence to decide whether to pursue conversational Siri support, ship a smaller Shortcuts integration, or defer the feature.

This document defines that investigation and the work that follows it. It does not commit SendMoi to a launch date or promise support for particular Siri phrases.

## Opportunity and hypothesis

SendMoi turns shared content into a polished email with recipient defaults, cleaned-up links, previews, and summaries. Siri could make that existing workflow available without navigating the share sheet.

The hypothesis: for supported public articles, a person can ask Siri to send the URL through SendMoi and their default recipient receives a useful, polished email with less interaction. Equivalent quality to the share extension is a question to measure, not an assumption.

Safari's preprocessor can supply the page title, selected text, descriptions, and X post text from the rendered page. URL-only input cannot reproduce all of that context. The native metadata fetch may still produce a good email for public articles, but selected passages, authenticated/paywalled pages, and JavaScript-rendered content need explicit comparison. Social sites are diagnostic cases, not additions to the initial shipping scope.

The value is both the ease of sending and the quality of what arrives. Generic email sharing may also become easier through Siri, so fewer taps alone are not a sufficient product advantage.

## Starting point

The repository already contains Gmail authentication and delivery, saved recipients, content enrichment, an App Group-backed queue, and a native share extension. Relevant implementation areas:

- `SendMoi/Services/GmailDeliveryService.swift`: delivery and email rendering.
- `SendMoi/Services/QueueStore.swift`: durable queue storage.
- `SendMoi/Services/RecipientStore.swift`: default and recent recipients.
- `SendMoi/Services/SharedContainer.swift`: shared storage and send-rate ledger.
- `SendMoiShare/ShareExtensionModel.swift`: share intake and delivery orchestration.
- `SendMoiShare/SafariPreprocessor.js`: rendered-page context capture.
- `SendMoi/Models.swift`: share and queued-email models.

The repository review found no App Intents, App Shortcuts, or Siri entity integration. Existing Foundation Models summarization does not expose the app's actions to Siri.

The queue persists work, but the current app does not guarantee delivery while fully terminated. A Siri entry point must distinguish queue acceptance from successful delivery.

Code review also identified existing concurrency defects: append is locked, but replace and whole-array saves are not transactional; app and extension flushers can select the same item and overwrite newer queue contents. The lock helper currently proceeds unprotected if opening the lock fails and does not check lock-acquisition success. The send-rate ledger also uses separate validation and recording with unguarded updates.

Delivery has an additional ambiguity: a timeout, cancellation, or lost response can occur after Gmail accepts a message. Retrying can then duplicate it. This is a conditional failure scenario, not evidence that every failed request duplicates. A stable Message-ID helps correlation but is not a documented Gmail idempotency guarantee.

Reusable services exist, but a headless delivery coordinator does not. Current orchestration mixes sending, queue handling, presentation state, and extension completion in a MainActor UI model. The project currently has two native targets and no test target or test files found in the repository review. Extraction and meaningful automated coverage are prerequisite work, not a trivial adapter.

## Prototype experience

1. The tester connects Gmail and sets a default recipient in SendMoi.
2. They open a public article in Safari on a compatible iPhone.
3. They ask Siri to send the article with SendMoi. “Send this with SendMoi” is the target phrase to investigate, not an established capability.
4. Siri obtains the URL and invokes the SendMoi action, requesting any confirmation the integration requires.
5. SendMoi uses its existing enrichment and email delivery pipeline.
6. The tester gets an accurate sent, queued, failed, or delivery-uncertain response and verifies the resulting message in the recipient inbox. Unknown server acceptance must not be disguised as a safe queued retry.

Use a tester-controlled recipient for delivery experiments.

## Scope

- One public article URL per invocation.
- Safari on one physical, Siri AI-compatible iPhone as the first source and device.
- An already connected Gmail account and an already configured default recipient.
- Existing email presentation and enrichment behavior, including existing fallbacks.
- A Shortcuts action as the controlled entry point for validating inputs and execution.
- The smallest legitimate mail-schema adoption needed to investigate conversational Siri execution.
- A tested headless delivery coordinator used by the app queue, share extension, and new intent.
- Intent behavior ignores `shareSheetAutoSendEnabled` entirely. Confirmation follows the intent's explicit design and system requirements.
- Preserve iOS 18 and macOS 15 deployment floors and keep both platform builds working, even though Siri experience testing starts on iPhone.

Defer named-recipient resolution, Contacts integration, photos, multiple links, dictated notes, searchable sent history, new summarization features, onboarding changes, marketing claims, and broad platform coverage. Those belong in a later scope decision.

## Questions the prototype must resolve

| Question | Evidence to collect |
| --- | --- |
| Can Siri resolve “this” to the Safari article URL? | Actual received input compared with the visible page, across several articles. |
| Do Apple's mail schemas fit SendMoi's specialized workflow? | Required intents/entities and draft lifecycle, with any mismatch documented. |
| Can the action complete without opening SendMoi? | Observed behavior with the app foregrounded, backgrounded, and terminated. |
| Can enrichment finish within the available execution time? | Timings and received output, including slow or unavailable metadata. |
| What confirmation does the user encounter? | Actual system interaction, cancellation behavior, and recipient visibility. The intent must not read the share-sheet Auto-send preference. |
| What happens when execution fails or repeats? | Queue contents, delivery attempts, recipient inbox, and spoken/visible result. |

Record device, OS build, Xcode/SDK version, language, and relevant Siri settings alongside results. Distinguish platform limitations from SendMoi implementation failures.

## Sequence

### 0. Settle platform and execution choices

Check the installed SDK and current Apple documentation for exact per-API availability, required companion mail actions, content transfer, execution modes, and confirmation requirements. Mail schemas originated in iOS 18; newer APIs and Siri runtime capabilities have their own requirements. Do not apply a blanket iOS 26 availability assumption. Use appropriate compile-time and runtime guards, following the repository's existing availability approach, without raising the deployment floors.

Default to placing the prototype intent in the app target and sharing the headless coordinator with the share extension. Confirm this approach against the selected APIs before coding. Add a dedicated App Intents extension only if a demonstrated requirement justifies its target, signing, App Group, and session/keychain access work. Target placement alone does not guarantee background execution or determine foreground presentation; execution modes and lifecycle behavior also matter.

Sketch the required draft/entity mapping. If the schema requires a broader mail-client model, record the cost and choose whether to continue before undertaking the refactor specifically for Siri. Record build checks for both iOS and macOS. Preserve older-system launch behavior as well as compilation.

Keep this first pass bounded to documentation and a compile probe. Record required companion schemas without building a mail client or connecting a send implementation. Stop early if the platform contract is a poor fit.

### 1. Compare content fidelity without App Intents

Choose a small, documented set of public articles plus diagnostic cases for selected text, X, paywalls, and JavaScript-rendered pages. Compare actual Safari share/preprocessor inputs with URL-only `fetchDraftPreview` output. Also compare locally rendered email output through the existing enrichment pipeline, because preview metadata alone does not establish final email quality. Do not send email for this comparison.

Record title, URL, excerpt/selected text, summary, image, missing context, and elapsed time. A small harness may be needed; this is cheaper than implementing Siri but is not zero work. Identify source categories where URL-only output is sufficient and where it is not. If ordinary public articles lose the product's value, revise or stop the Siri hypothesis before integration work. Failures on out-of-scope social pages alone do not invalidate the public-article prototype.

Before collecting results, freeze a set of 10 public text articles across at least five domains, plus separate diagnostic cases. Proposed prototype gate: correct source URL on 10/10; accurate title and a substantive, source-supported summary on at least 8/10; and a relevant image on at least 4 of 5 preselected articles whose normal Safari share supplies one. Inspect excerpt/selected-text differences separately; URL-only input is not expected to preserve a user's selection. Choose summary-eligible articles with sufficient body text and record baseline share output. These are product thresholds for this experiment, not statistical reliability claims. Do not substitute easier URLs after seeing results; a miss means explicitly narrow the promise or defer.

Build a small reusable enrichment/rendering seam for this comparison and the next probe. It does not need Gmail credentials or the full queue/storage test architecture.

### 1a. Probe Siri without sending

Create a development-only intent that accepts/resolves content, runs enrichment with an explicit budget, and returns a preview. It must neither write the outbound queue nor call Gmail. Reuse the fidelity harness. Test explicit Shortcuts input and Siri references to the current Safari page, with the app foregrounded, backgrounded, and terminated.

Use a legitimate preview/draft schema if the platform supports the required flow; do not claim to have sent mail or misuse a send schema to return a preview. Required send companions may be compile-only or explicitly unavailable in the probe. If only a custom Shortcut works, report that narrower finding rather than treating it as proof of mail-schema routing.

Record received content, enrichment latency, foreground transitions, and observed confirmation behavior. This probe establishes only the behavior it exercises: real send confirmations, Gmail latency, and the complete send lifecycle still require later validation. Decide whether Siri, Shortcuts alone, or neither warrants further work before the delivery refactor. Existing delivery defects remain independently worth fixing if Siri is deferred.

### 2. Establish delivery safety and automated coverage

Before adding another sending entry point, implement and test a queue/delivery state contract. This work is valuable independently of Siri and should be reviewable separately:

- Replace stale whole-array writes with atomic operations by item ID. Serialize the full read-modify-write transaction across processes, including replacement, deletion, claims, and completion. Fail safely on lock errors. Simply wrapping `save` in a lock does not fix stale snapshots; avoid nested locking when restructuring append.
- Give a delivery attempt exclusive ownership of its item through a durable claim or equivalent design before network activity. An expired or abandoned delivery claim transitions to delivery uncertain, never automatically back to queued. This intentionally treats even a possible pre-submission crash conservatively. Do not hold a file lock across network awaits or assume that locking writes prevents concurrent sends.
- Preserve a stable item identity, avoid duplicate queue insertion, and add a stable MIME Message-ID for correlation. Distinguish retries of one operation from a new deliberate send of the same URL. Message-ID does not replace delivery ownership or guarantee remote deduplication.
- Persist delivery state and classify known pre-send failure separately from unknown server acceptance. Ambiguous attempts never auto-retry. Surface them in the existing Offline Queue UI with “Send again” and “Discard” actions; explain that sending again may duplicate an email and suggest checking Sent mail manually first. Discard removes local work only and does not recall a message. Exclude uncertain items from bulk retry. Server reconciliation and additional Gmail scopes are out of scope; retain the current gmail.send, email, and openid scopes.
- Make rate-limit check-and-record one locked transaction immediately before a Gmail send attempt. Count attempts, including failures, rather than successful sends; do not add reservation/release states. Blocked attempts do not consume another slot. A crash after recording may conservatively consume a slot without sending. Update user-facing limit language and tests to match this deliberate policy change.

Add a test target or equivalent runnable harness with isolated storage, injected transport, and controllable time. Cover concurrent claims, app/extension-style writers, stale update/deletion, lock failure, acceptance followed by response loss, timeout/cancellation races, crash recovery, and rate-limit boundaries. Use deterministic fault injection instead of relying on a few manual sends. Add test seams only where needed: a transport closure/protocol, storage location or store adapter, and a clock. Static namespaces do not inherently require converting all five storage/session helpers; production wrappers can retain existing defaults. Reuse the enrichment seam from step 1. Storage isolation and cross-process coordination need explicit implementation effort; avoid unsupported hour/day estimates before inspecting the required seams.

Exit gate: no sending intent until these tests demonstrate the agreed state contract and uncertain acceptance cannot silently trigger a blind retry. This is not a promise of exactly-once delivery through Gmail.

### 3. Extract and adopt a headless delivery coordinator

Use the reusable authentication, storage, enrichment, and sending services underneath a coordinator that has no SwiftUI presentation or NSExtensionContext responsibilities. Define typed results for sent, safely queued, failed, and delivery uncertain. Sent means Gmail accepted the request; it does not establish inbox receipt.

Repoint both existing app queue processing and share-extension delivery at the coordinator, keeping UI and extension completion in their adapters. Preserve the share sheet's edit/grace behavior and regression-test it. Explicitly test the hot-path change from direct send with fallback queueing to durable persistence and exclusive claim before submission. Measure added file writes/notifications, cancellation during the grace period, and interaction with the watchdog; an app queue flusher must not send a draft while it is still editable. The current share path can close normally after queueing a delivery error; that behavior must not become a successful-send result in an intent. Implement steps 2 and 3 in coordinated increments if necessary, but finish both before step 4.

Budget timing explicitly. Current baselines are an 8-second delivery watchdog, a 4-second auto-send preview wait, a 750-millisecond manual preview wait, and summary deadlines of 5 seconds in an appex or 12 seconds in the app. The auto-send watchdog also includes its grace/commit intervals. These are existing share UX choices, not Siri execution guarantees. Replace context inferred solely from bundle type with an explicit execution budget where needed.

### 4. Prove explicit-input execution

Expose a minimal SendMoi action in Shortcuts accepting a URL and using the saved default recipient. Invoke the tested coordinator and map its result truthfully into system feedback. Validate missing setup, invalid recipient, safe queueing, uncertain delivery, rate limits, and cancellation before adding onscreen-context uncertainty.

### 5. Prove the Siri experience

Adopt the applicable schemas and content handling, then test the target Safari workflow on-device. Record working phrases and whether the system requires app naming, clarification, confirmation, or foreground execution. Success in Shortcuts alone does not count as conversational Siri success.

### 6. Evaluate and choose a direction

Write a short findings report with observed behavior, a demo or reproducible walkthrough, failures, required engineering work, and a recommendation. Choose one of the outcomes below before writing a production spec.

### 7. Specify and build the selected product

If proceeding, write the production spec from the prototype evidence. Define supported inputs and platforms, recipient selection, confirmation rules, draft semantics, delivery and retry behavior, duplicate prevention, accessibility, setup recovery, privacy implications, and acceptance tests. Then create the implementation plan, harden the feature, and validate through TestFlight before making availability claims.

## Validation and success criteria

Test several public article URLs through both explicit Shortcuts input and the target Siri flow. Capture the input, recipient, queue state, delivery result, and received email for each attempt.

The prototype passes the core experience when:

- Siri supplies the intended article and invokes SendMoi through a repeatable interaction.
- The configured recipient receives the correct URL and existing SendMoi email presentation.
- Automated concurrency and fault-injection tests pass before live intent sends; each confirmed invocation produces one email in the observed successful cases.
- Feedback says sent only after Gmail accepts the send. Inbox inspection separately verifies receipt.
- Offline or interrupted execution does not silently lose an accepted item or claim it was sent.
- Missing Gmail access or a default recipient produces actionable feedback without sending.
- Cancellation before confirmation produces no outbound email.
- An ambiguous post-submission failure reports delivery uncertainty and does not silently schedule an automatic resend.
- The app and share extension still build for iOS and macOS, with newer APIs gated and older supported OS behavior checked.

Also exercise slow metadata, unavailable enrichment, expired/revoked Gmail access, app termination, and repeated invocation. Deliberately test SendRateLimiter feedback and recovery at the production limits of 20 sends per five minutes, 50 per hour, and 150 per day using injected time and ledger fixtures rather than sending bulk test email. Retain automated coverage for successful delivery followed by interrupted cleanup or a lost response; manual success does not establish exactly-once delivery.

Enrichment failure may use the existing fallback. If the action can only queue, requires opening the app, or cannot obtain the onscreen URL, report that limitation explicitly and evaluate whether the remaining experience is still useful.

## Decision after the prototype

| Outcome | Next step |
| --- | --- |
| URL-only fidelity is insufficient for ordinary public articles | Revise the input/content promise or defer before Siri implementation. Track existing delivery defects independently. |
| Conversational Siri works reliably and preserves SendMoi's value | Write the production Siri/Shortcuts spec and implementation plan. |
| Explicit-input Shortcuts works, but conversational Siri is unreliable or a poor schema fit | Specify a smaller Shortcuts release; document Siri support limits. |
| Delivery or lifecycle behavior is not trustworthy | Address the demonstrated delivery issue before productizing either entry point. |
| Required integration is disproportionate to the benefit | Defer with documented findings and conditions for revisiting. |

## Deliverables and completion boundary

The next phase should first produce a platform decision note, fidelity report, and non-sending Siri probe findings, then, only if proceeding, separately reviewable delivery-safety/coordinator changes with automated tests, prototype code, an on-device test procedure, and a findings report. The production feature spec follows the findings; the delivery state contract must be designed before its prerequisite refactor.

Keep this brief at `docs/superpowers/plans/2026-09-08-sendmoi-siri-app-intents.md`. Follow-up plans belong in the same directory, and the eventual production spec belongs in `docs/superpowers/specs/`.

The planning brief was completed before implementation. The subsequent non-sending prototype and its limits are recorded in the linked findings. No outbound test emails or delivery refactor are part of that completed probe.

## References

Apple sources reviewed during the September 8, 2026 opportunity assessment. Recheck against the installed SDK before implementing:

- [Apple Intelligence and Siri AI](https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai)
- [Build intelligent Siri experiences with App Schemas, WWDC26](https://developer.apple.com/videos/play/wwdc2026/240/)
- [Mail app schema domain](https://developer.apple.com/documentation/appintents/app-schema-domain-mail)
- [Apple's Siri AI announcement](https://www.apple.com/newsroom/2026/06/apple-introduces-siri-ai-a-profoundly-more-capable-and-personal-assistant/)
- [Bring your app to Siri, WWDC24: mail domains introduced with iOS 18](https://developer.apple.com/videos/play/wwdc2024/10133/)
- [App Intent execution modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes-5zhmb)
- [Gmail messages.send: no documented idempotency parameter or Message-ID deduplication contract](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/send)

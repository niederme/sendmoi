# Use SendMoi through Siri

Date: September 11, 2026
Status: Active planning brief. Implementation has not started.

## What we want

Someone reading an article on their iPhone can ask Siri to send it through SendMoi. SendMoi uses the Gmail connection and recipient settings they already configured, then tells them what happened.

**You speak → Siri calls SendMoi with the article → SendMoi sends through Gmail.**

“Send this with SendMoi” is the target experience, not a phrase or capability we have verified. “Send this to myself” is appropriate only when the configured recipient is actually the user; otherwise the interaction must identify the saved recipient accurately.

## Why SendMoi exists

John already tried solving this with Shortcuts and could not reliably script Apple Mail. SendMoi was built around the Gmail API to own the sending workflow. This update should make that app usable by voice.

The previous investigation became centered on Shortcuts testing, content extraction, and Apple's broader mail model. This brief replaces that roadmap. We retain its documents and code as historical evidence, not instructions to keep executing the old plan.

## The intended experience

1. The user has connected Gmail and chosen a default recipient in SendMoi.
2. They open an article in Safari and ask Siri to send it with SendMoi.
3. Siri identifies the article and invokes SendMoi. If it cannot identify the content, it asks for clarification or explains the limitation. It must not silently select a different page or clipboard item.
4. The first sending prototype names the article and recipient and asks for explicit confirmation. Cancelling sends nothing.
5. SendMoi uses its existing Gmail-backed workflow and email presentation.
6. The response distinguishes sent, saved for later delivery, failed, and uncertain delivery. “Sent” requires confirmed Gmail acceptance; it does not promise inbox arrival.

The desired experience avoids navigating the app or building a personal Shortcuts workflow. Whether Siri can do this with SendMoi in the background or closed is something to prove on iPhone. If opening SendMoi is necessary, record that as a product limitation and decide whether that version is worthwhile.

## How we approach it

Expose a narrow SendMoi action through App Intents. Apple describes App Intents as app actions that Siri can invoke. App Shortcuts can provide discoverability and spoken phrases without requiring the user to configure a workflow in the Shortcuts app. These developer interfaces can support a voice experience; they do not make Shortcuts the product. [Apple: creating an app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent), [Apple: App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts).

Use the smallest supported integration that can deliver the intended experience. Do not assume a custom action automatically receives the current Safari page. Do not assume adopting Apple's full mail schemas is required merely because SendMoi sends email. The earlier mail-domain scope finding remains relevant to that particular integration route, not a blanket reason to abandon voice support. If the desired contextual Siri behavior requires a broader contract, bring that specific limitation back as a product decision.

## Work in order

### 1. Prove Siri can reach SendMoi

Use the existing non-sending **Check SendMoi Connection** control on a physical iPhone. Try its registered spoken phrase and record the exact response. The expected fixed response is “SendMoi probe connected. Nothing sent or queued.”

Keep the previous implementation hold until that existing control returns successfully. A manual tap in iOS Shortcuts can diagnose whether the action itself works, but it does not satisfy the voice milestone. If the device or manual interaction is unavailable, pause here rather than add more instrumentation or resume Mac routing work.

### 2. Prove the article reaches SendMoi

After the control works, validate a non-sending action that receives the current Safari article and returns its title and URL. Start with one known public article, then repeat on several pages. Record what Siri heard, which URL arrived, any clarification, and whether SendMoi opened.

Test async work and foreground/background/closed-app behavior here. An explicitly supplied URL is a diagnostic comparison, not proof that Siri understands “this.” Choose timing budgets from observed iPhone behavior and the desired waiting experience; do not inherit the share sheet's watchdog or claim one successful run establishes the platform's maximum allowance.

**Decision:** proceed only if the voice-and-content interaction works, or John explicitly accepts a narrower experience. If it requires manually building a workflow, it has not met this brief.

### 3. Connect that proven entry point to Gmail

Write a focused implementation spec based on what steps 1 and 2 establish. Reuse SendMoi's existing authentication, recipients, rendering, and Gmail transport. Do not create a second independent delivery implementation or script Apple Mail.

Before enabling actual sending, address the previously identified cross-process queue ownership and ambiguous-send risks in the shared delivery path. An interrupted response after Gmail acceptance must not cause blind automatic resend. Preserve existing share-sheet behavior and verify the changed paths. Keep Siri confirmation independent of the share-sheet Auto-send preference.

Then test confirmed sends to a tester-controlled recipient, verifying the received article, recipient, email, and reported outcome. These sends require separate explicit authorization; today's task is planning.

### 4. Decide what can ship

The update needs observed voice invocation, correct article input, confirmed Gmail delivery, truthful error/queue responses, and cancellation that sends nothing. Repeat across supported app states and common failure conditions. A single successful email is not an exactly-once guarantee.

Assess whether the received email is useful for this voice workflow using existing formatting and fallback behavior. Identify content limitations honestly. A broad enrichment rewrite or the old ten-article score is not the gate for proving Siri invocation, although unsuitable content can still block shipping.

## What stays separate

The enrichment candidate remains paused quality work, including a potentially separable challenge-page rejection fix. It needs its own review and relevant share-path coverage before shipping. It is not a prerequisite investigation for voice routing.

This first update excludes a general mail client, inbox reading, arbitrary recipient lookup, multiple articles, attachments, new summarization features, and a Mac voice rollout. Preserve existing iOS/macOS support when implementation changes shared code.

## Where we are now

The probe and its control exist. Builds and action discovery were verified; end-to-end execution and Siri voice behavior were not. Both experiment branches were pushed. Those are useful starting materials, not a completed voice feature.

**Next action: manually verify the existing control on iPhone, beginning with Siri. No new feature code, corpus run, or delivery test is needed before that.**

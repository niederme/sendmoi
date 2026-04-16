SendMoi Browser Extension Plan

Safari + Chrome (Mac, iOS, iPadOS)
Date: 2026-04-16
Status: Draft

⸻

Overview

This plan defines a browser extension strategy for SendMoi as a companion capture layer to the installed app.

The extension is not a full client. It is a fast, reliable way to save content from the web into SendMoi, with minimal friction and strong platform coverage.

The goal is to ship a shared WebExtension core that works across:
  •	Safari (macOS, iOS, iPadOS)
  •	Chrome (macOS)

…and integrates cleanly with the native SendMoi app and backend.

⸻

Principles

1. Capture-first, not feature parity

The extension exists to get content into SendMoi quickly — not to recreate the app.

2. Thin extension, strong app

The native app owns:
  •	auth
  •	sync
  •	storage
  •	editing
  •	organization

The extension gathers context and submits it.

3. One core, multiple shells

All logic should live in a shared layer. Browser-specific code is minimized.

4. API-first architecture

Default communication is extension → SendMoi API
Native bridges are additive, not foundational.

5. Mobile realism

iOS/iPadOS Safari extensions are constrained. Design for quick capture, not complexity.

⸻

Platform Strategy

Safari (Primary)

Safari is the only path to:
  •	macOS
  •	iPhone
  •	iPad

Shipped as part of the SendMoi app bundle.

macOS
Full-featured extension:
  •	toolbar UI
  •	context menus
  •	content scripts
  •	popup interaction

iOS / iPadOS
Constrained but valuable:
  •	save current page
  •	lightweight UI
  •	handoff to app

Do not attempt:
  •	complex overlays
  •	heavy editing workflows

⸻

Chrome (Secondary)

macOS only.

Supports:
  •	full extension APIs
  •	context menus
  •	keyboard shortcuts
  •	optional native messaging

No meaningful path on iOS/iPadOS.

⸻

Core User Experience

Primary Actions
  1.	Save page
  2.	Save selection
  3.	Save link
  4.	Save to default destination (Inbox)
  5.	Open in SendMoi

That’s enough for v1.

⸻

Popup UX

Top
  •	page title
  •	domain
  •	save state

Middle
  •	destination (default: Inbox)
  •	optional note
  •	optional tags (lightweight)

Bottom
  •	Save
  •	Open app
  •	Settings

⸻

Context Menu
  •	Save to SendMoi
  •	Save selection to SendMoi
  •	Save link to SendMoi

⸻

Success State
  •	Immediate feedback (checkmark)
  •	“Saved to Inbox”
  •	Optional: undo / open

No list management inside the extension.

⸻

Architecture

Three-layer model

1. Capture Core (shared)
Pure TypeScript.

Responsibilities:
  •	extract URL / canonical URL
  •	title + metadata
  •	selected text
  •	Open Graph / meta parsing
  •	basic content classification
  •	dedupe fingerprint
  •	normalized payload

No browser APIs here.

⸻

2. Extension Shells
Browser-specific:
  •	manifest configuration
  •	permissions
  •	popup wiring
  •	context menus
  •	messaging layer
  •	build output

Targets:
  •	Safari extension target (Xcode)
  •	Chrome extension (Manifest V3)

⸻

3. SendMoi App + Backend
Handles:
  •	auth/session
  •	API tokens
  •	sync + retries
  •	storage
  •	deep linking
  •	offline queue (future)

⸻

Communication Strategy

Default: API-first

Extension → SendMoi backend

Pros:
  •	simpler architecture
  •	cross-browser consistency
  •	avoids native complexity

⸻

Native bridge (optional)

Safari
Bundled app + extension allows native interaction if needed.

Chrome (macOS)
Possible via native messaging.

⸻

Recommendation

Do not build native messaging in v1.

Add later only if needed for:
  •	secure session sharing
  •	local file access
  •	app wake behavior
  •	offline queueing

⸻

Permissions Strategy

Keep this tight.

Required
  •	activeTab
  •	contextMenus
  •	storage
  •	scripting (content scripts)

Avoid
  •	broad “read all sites” messaging
  •	unnecessary background behavior

Trust is critical.

⸻

Mobile Considerations (iOS / iPadOS)

Reality:
  •	limited UI surface
  •	less predictable behavior than desktop
  •	no Chrome extension parity

Design approach

Treat mobile as:

“Quick save from Safari, then continue in app”

Not:

“Mini version of SendMoi”

⸻

Share Extension (Future)

Separate but related.

Why it matters

Safari extension ≠ system-wide sharing

Likely need both:
  •	Safari extension → browser capture
  •	Share extension → cross-app capture

Not part of v1, but should be planned alongside.

⸻

Code Organization

sendmoi/
  apps/
    mac-app/
    ios-app/
    safari-extension/
    chrome-extension/
  packages/
    capture-core/
    extension-ui/
    api-client/
    auth-shared/
    types/


⸻

Roadmap

Phase 1 — Desktop MVP
  •	Safari (macOS)
  •	Chrome (macOS)
  •	shared core
  •	save page / selection / link
  •	basic popup
  •	API integration
  •	open-in-app

⸻

Phase 2 — Mobile Safari
  •	iOS + iPadOS support
  •	simplified UI
  •	reliable page capture
  •	app handoff

⸻

Phase 3 — Smarter Capture
  •	article extraction
  •	highlights
  •	tags
  •	screenshots
  •	rules / auto-destination
  •	keyboard shortcuts

⸻

Risks

1. Overbuilding UI

Browser popups are not a product surface. Keep it transactional.

2. Auth friction

If login feels weird or duplicated, users will drop off.

3. Platform drift

Safari vs Chrome differences can quietly fork the codebase.

4. Mobile expectations

iOS Safari extensions are useful but limited — design accordingly.

⸻

Key Decisions (for review)
  1.	API-first vs native bridge in v1
→ Recommendation: API-first
  2.	Scope of popup UI
→ Recommendation: minimal (capture only)
  3.	Mobile ambition level
→ Recommendation: constrained, fast capture
  4.	Shared core investment
→ Non-negotiable — prevents long-term fragmentation

⸻

Summary

This should ship as:

A fast, reliable way to save anything from the web into SendMoi.

Not a browser client. Not a second app.

If this stays focused, it becomes one of the highest-leverage surfaces you can build.
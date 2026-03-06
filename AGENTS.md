# Repository Instructions

## Commit Workflow
- Before every commit, review `README.md` and `HANDOFF.md`.
- Update `README.md` whenever setup steps, commands, behavior, or other user-facing documentation changed.
- Update `HANDOFF.md` whenever the working branch, current focus, recent changes, open items, or resume steps changed.
- Do not finalize a commit until those files are either updated or explicitly confirmed to still be accurate.

## Git Workflow
- Work from `main` on short-lived branches named `codex/*`.
- Do not push directly to `main` unless explicitly told to.
- Commit at sensible, verifiable milestones without waiting for approval.
- Multiple commits per branch are fine; keep them scoped and readable.
- Leave changes PR-ready when a task is complete.
- Prefer squash merge into `main`.
- This is a solo-review workflow: no required approvals, but do not merge until the diff has been reviewed and relevant tests/checks have passed.
- Do not include unrelated working tree changes in commits unless explicitly requested.

## GitHub Issues Workflow
- Treat messages prefixed with `GHI:` as a request to create a GitHub issue directly.
- Classify issue type and labels based on context (for example: `bug`, `enhancement`, `chore`) unless the user explicitly forces a type.
- If the user includes a type hint inline (for example: `GHI: [bug] ...`), honor it.
- If required details are missing, ask a short follow-up question before creating the issue.
- If the user provides screenshots/videos, include them in the issue:
  - use existing URLs directly when available
  - otherwise upload media into the repo (for example under `docs/bugs/...`) and link it in the issue body.

# Repository Instructions

## Delivery Lifecycle Workflow

### 1) Start New Feature/Fix Work
- Write or identify the GitHub issue first. Every branch should map to one primary issue.
- Do not push directly to `main`; all work happens on a task branch.
- Work from `main` on short-lived branches named `codex/*`.
- Start from latest `main`:
  - `git checkout main`
  - `git pull --ff-only`
  - `git checkout -b codex/<short-slug>`
- For concurrent work, use separate branches and prefer separate worktrees:
  - `git worktree add ../sendmoi-<short-slug> -b codex/<short-slug> main`
- Keep scope tight: branch changes should stay focused on the linked issue.

### 2) Implement And Commit
- Commit at sensible, verifiable milestones without waiting for approval.
- Multiple commits per branch are fine; keep them scoped and readable.
- Do not include unrelated working tree changes in commits unless explicitly requested.
- Before every commit, review `README.md` and `HANDOFF.md`.
- Update `README.md` whenever setup steps, commands, behavior, or other user-facing documentation changed.
- Update `HANDOFF.md` whenever the working branch, current focus, recent changes, open items, or resume steps changed.
- Do not finalize a commit until `README.md` and `HANDOFF.md` are updated or explicitly confirmed to still be accurate.

### 3) When Asked To Open A PR
- Confirm the issue number to link in the PR. If missing, ask before creating the PR.
- Complete relevant tests/checks.
- Sync branch right before PR creation:
  - `git fetch origin`
  - `git rebase origin/main` (or merge `origin/main` when rebase is not appropriate)
- Resolve conflicts, rerun checks, then push:
  - normal push: `git push -u origin codex/<short-slug>`
  - after rebase: `git push --force-with-lease`
- Open PR against `main` and link the issue in the PR body using `Closes #<issue-number>`.
- Ensure the PR is reviewable and checks are passing before merge; squash merge is preferred.
- This is a solo-review workflow: no required approvals, but do not merge until diff and checks are complete.

### 4) After Merge Confirmation
- Sync local `main`:
  - `git checkout main`
  - `git pull --ff-only`
- Clean up feature branch:
  - `git branch -d codex/<short-slug>` (if this fails after squash merge, use `git branch -D codex/<short-slug>`)
  - `git push origin --delete codex/<short-slug>`
- Clean up parallel workspace metadata when used:
  - `git worktree prune`

## GitHub Issues Workflow
- Treat messages prefixed with `BUG:` or `ISSUE:` as a request to create a GitHub issue directly.
- Classify issue type and labels based on context (for example: `bug`, `enhancement`, `chore`) unless the user explicitly forces a type.
- If the user includes a type hint inline (for example: `ISSUE: [bug] ...`), honor it.
- If required details are missing, ask a short follow-up question before creating the issue.
- If the user provides screenshots/videos, include them in the issue:
  - use existing URLs directly when available
  - if media is local-only, ask for a shareable URL or confirm the user will attach it manually (do not require committing media into this repo).

# Repository Instructions

## Commit Workflow
- Before every commit, review `README.md` and `HANDOFF.md`.
- Update `README.md` whenever setup steps, commands, behavior, or other user-facing documentation changed.
- Update `HANDOFF.md` whenever the working branch, current focus, recent changes, open items, or resume steps changed.
- Do not finalize a commit until those files are either updated or explicitly confirmed to still be accurate.

## Git Workflow
- Work from `main` on short-lived branches named `codex/*`.
- Do not push directly to `main` unless explicitly told to.
- Before opening a PR, sync your branch with the latest `origin/main` (`git fetch origin` then `git rebase origin/main`).
- If rebase is not appropriate for the branch, merge `origin/main` before opening the PR.
- For parallel tasks, keep one branch per task (and prefer one worktree per branch) so work can proceed on multiple branches at once without cross-contamination.
- Commit at sensible, verifiable milestones without waiting for approval.
- Multiple commits per branch are fine; keep them scoped and readable.
- Leave changes PR-ready when a task is complete.
- Prefer squash merge into `main`.
- This is a solo-review workflow: no required approvals, but do not merge until the diff has been reviewed and relevant tests/checks have passed.
- Do not include unrelated working tree changes in commits unless explicitly requested.

## Delivery Lifecycle Workflow

### 1) Start New Feature/Fix Work
- Write or identify the GitHub issue first. Every branch should map to one primary issue.
- Start from latest `main`:
  - `git checkout main`
  - `git pull --ff-only`
  - `git checkout -b codex/<short-slug>`
- For concurrent work, use separate branches and prefer separate worktrees:
  - `git worktree add ../sendmoi-<short-slug> -b codex/<short-slug> main`
- Keep scope tight: branch changes should stay focused on the linked issue.

### 2) When Asked To Open A PR
- Confirm the issue number to link in the PR. If missing, ask before creating the PR.
- Complete the commit workflow checks (`README.md` / `HANDOFF.md`) and run relevant tests/checks.
- Sync branch right before PR creation:
  - `git fetch origin`
  - `git rebase origin/main` (or merge `origin/main` when rebase is not appropriate)
- Resolve conflicts, rerun checks, then push:
  - normal push: `git push -u origin codex/<short-slug>`
  - after rebase: `git push --force-with-lease`
- Open PR against `main` and link the issue in the PR body using `Closes #<issue-number>`.

### 3) After Merge Confirmation
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

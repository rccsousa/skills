---
name: merge-pr
license: MIT
description: Use when a PR has been reviewed, approved, and is ready to merge. Calls /pr-ready first — refuses to merge if BLOCKED. On green, prompts merge method (merge/squash/rebase) and runs gh pr merge. Triggers - "/merge-pr", "merge it", "click the merge button", "ship the PR".
disable-model-invocation: true
---

# merge-pr

Execute the actual merge. Verification gates upstream via `/pr-ready` — this skill is the action that follows.

## Pipeline

```
resolve PR → /pr-ready (verify) → pick merge method → HITL approve → gh pr merge → post-merge surface
```

## Arguments

- `$1` (optional) — PR number. Else current branch via `gh pr view --json number`.
- `--method <merge|squash|rebase>` — override method (default: squash for typical strict-PR repos)
- `--delete-branch` — delete remote branch after merge (default: ask)

## Steps

### 1. Resolve PR

- `$1` given → use it.
- Else: `gh pr view --json number,title,headRefName,baseRefName,mergeStateStatus`.
- No PR for branch → halt with "no PR found, run /create-pr first".

### 2. Verify mergeability

Invoke `/pr-ready <number>` (or run `bash scripts/pr-checks.sh <number>` directly).

- JSON `.ready == true` → continue.
- Otherwise → print the BLOCKED checklist verbatim + halt. Don't ask "merge anyway?" — strict-PR repos never bypass.

If user explicitly says "merge anyway, I'm overriding" — proceed but require a second explicit "yes I'm sure" before calling `gh pr merge`. Flag the override once.

### 3. Pick merge method

Default = `squash` (matches one-PR-per-feature pattern). Skip the prompt if:
- `--method` flag given, OR
- PR has exactly 1 commit (squash == merge == noop difference, just squash silently)

Otherwise ask:

```
PR #1234 — feat(my-feature): xyz (5 commits)
Method? [squash (default) / merge / rebase]
```

### 4. HITL approve

Surface final summary:

```
About to merge:
  PR #1234 — feat(my-feature): xyz
  base: main ← feat/my-feature
  method: squash
  delete branch: yes/ask
```

Wait for explicit "merge" / "yes" / "go". Irreversible action — gate is mandatory.

### 5. Execute merge

```bash
gh pr merge <number> --<method> [--delete-branch]
```

Capture output. On failure (e.g. base diverged mid-flow):
- Print error verbatim.
- Suggest `/catch-up-main` if mergeable state went stale.
- Don't retry automatically.

### 6. Post-merge surface

```
✓ Merged PR #1234 via squash
  commit: <SHA on base>
  branch: <deleted | retained>

Next:
- archive plan: plans/<slug>.md → plans/archive/
- archive followups: .claude/followups/<slug>.md → alongside plan
- local branch: git branch -d <branch> (if not auto-deleted)
- pull base: git checkout <base> && git pull
```

Don't auto-archive plans / delete local branches. Surface as a checklist.

## Halt conditions

- `/pr-ready` returns BLOCKED → don't merge, print checklist.
- Base branch diverged (`mergeStateStatus != "CLEAN"`) → run `/catch-up-main`.
- User declines at HITL gate → exit cleanly, no side effects.
- `gh pr merge` returns non-zero → surface output, halt.

## Out of scope

- Verifying mergeability → `/pr-ready` (called internally)
- Opening the PR → `/create-pr`
- Post-merge plan archival → manual (surfaced as checklist)

## Why this skill exists

`pr-ready` told you the PR is green. `merge-pr` is the action button. Splitting verb from verb keeps the gate honest (no "ready → auto-merge" footgun) and lets `/pr-ready` be a pure inspector callable from anywhere.

The action is irreversible at the GitHub level, so two explicit gates (`pr-ready` green + HITL approve) before the call — required for blast-radius actions.

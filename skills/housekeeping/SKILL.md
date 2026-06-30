---
name: housekeeping
description: Tidy a repo after a task wraps - prune stale worktrees, delete plan files for merged PRs, and report what's left. Use when the user says "/housekeeping", "clean up the repo", "tidy up", or after a feature merges.
disable-model-invocation: true
---

Routine cleanup pass. **Staged escalation**: pass 1 auto-removes only the obviously-safe stuff (merged-and-clean), then the user directs further passes ("kill X, Y, Z", "prune branches too", "leave only A and B"). Don't try to nuke everything in one shot — surface the risky candidates with their state and let the user call it.

## Mental model

- `git worktree remove --force <wt>` **preserves the branch ref** — unpushed commits stay on the branch. Only **uncommitted dirty files** are lost. This is what makes pass-2 ("kill the dirty ones") safe to do on user command without elaborate stash dances.
- `git worktree remove` already deletes the folder. `git worktree prune` only cleans stale admin entries under `.git/worktrees/` — there is no separate "prune the folders" step.
- `git branch -D` refuses branches currently checked out by a worktree (built-in safety). Lean on this when bulk-deleting — don't pre-filter the keepers, let git refuse them.

## Inputs the user may give you

- A scope hint: "just plans", "just worktrees", "everything", or a kill list ("nuke fix-db-migrations and local-demo").
- If the user has multiple Claude sessions running concurrently, ask once for active session IDs so you don't yank their worktrees. Otherwise assume current session only.

## Steps

### 1. Snapshot

```bash
git worktree list
ls plans/
```

### 2. Per-worktree state table

```bash
bash ~/.claude/lib/housekeeping-snapshot.sh
```

Output JSON: `{count, auto_removable:[...], needs_decision:[...], all:[...]}`. Each worktree has `{name, path, branch, lock, dirty, unpushed, pr_number, pr_state, pr_merged_at, auto_remove_safe}`.

Render `needs_decision` as a table for the user: `name | lock | branch | dirty=N | unpushed=N | PR=#NNN/STATE`.

### 3. Pass 1 — auto-remove safe worktrees

For each in `auto_removable` (lock unlocked/dead + dirty=0 + PR MERGED):

```bash
git worktree remove --force <path>
```

Then `git worktree prune`. Everything in `needs_decision` waits for user direction.

### 4. Plans — delete what's merged, keep what's load-bearing

For each `plans/*.md`, find the related PR via keyword/branch-name search:

```bash
gh pr list --state all --search "<keyword>" --json number,state,headRefName --limit 5
```

Disposition:
- PR merged + branch gone → delete.
- Referenced from `CLAUDE.md` (phase orchestrators) → KEEP regardless of PR state.
- Plan matches active untracked work in the main checkout → KEEP.
- PR open / closed-without-merge → list it, ask the user.

### 5. Report — then wait for follow-ups

```
worktrees: removed N (merged+clean), kept M
  • <name>  — <one-line state>: dirty=X, unpushed=Y, PR=#NNN/STATE
plans:     removed N (merged), kept M (active/orchestrator)
branches:  not touched — <orphan branch list>; confirm before -D
```

Then **wait**. The user typically follows up with one of:

- *"kill X, Y, Z as well"* → just remove them (`git worktree remove --force`). Don't re-ask about dirty files — the kill list is the confirmation.
- *"prune branches too"* / *"leave only X and Y"* → run the branch sweep below.
- *"all done"* → stop.

### 6. Branch sweep (only on explicit user direction)

Pattern: user names the keepers ("leave only A and B"), you delete the rest with `-D` (catches unmerged too).

```bash
git fetch --prune origin                       # drop stale remote-tracking refs first
git branch --format='%(refname:short)' \
  | rg -v '^(main|<keeper-1>|<keeper-2>)$' \
  | rg -v '^$' \                                   # skip empty current-branch line when cwd isn't a worktree
  | while read b; do git branch -D "$b"; done
```

Notes:
- Don't pre-filter the keepers from the delete list — git refuses to delete branches in use by worktrees, which is a built-in safety net. Letting git surface those errors is fine.
- `git branch --format=...` from a non-worktree cwd (e.g. `.worktrees/`) emits an empty line for the missing current branch. Filter it with `rg -v '^$'` or you'll get a confusing `branch '*' not found` error.
- Squash-merged branches don't show under `--merged main`. When the user says "merged" they usually mean "PR merged" — use `gh pr list --state merged --head <branch>` if you need to verify before deleting.

## Don'ts

- Don't `git worktree remove -f -f` to override ALIVE-PID locks. Those are running agents.
- Don't delete plans that match active untracked work in the main checkout.
- Don't bulk-delete branches without an explicit keeper list from the user.
- Don't run this inside a worktree owned by another session — run from the primary checkout.
- Don't conflate "remove worktree" with "lose work" in your reporting — committed work survives on the branch ref; only uncommitted dirty files are lost. Be precise so the user can decide.

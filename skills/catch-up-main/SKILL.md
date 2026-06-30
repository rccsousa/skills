---
name: catch-up-main
description: Use when a feature branch has diverged from main and needs to absorb new upstream changes (conflicts after a sibling PR merged, CI complaining about "not up to date", reviewer asks to sync). Chooses merge vs rebase, resolves conflicts with take-ours-for-superset defaults, verifies typecheck+tests, lax commit+push.
disable-model-invocation: true
---

# catch-up-main

Bring a feature branch up to date with `origin/main` and resolve conflicts.

## Pre-authorization

Invoking this skill is **explicit user authorization to commit + push the merge/rebase result** without re-asking, overriding the global "wait for approval before committing/pushing" rule in CLAUDE.md. Scope: only the catch-up commit (auto-generated merge message or rebase result) on the current branch's own remote. Does NOT authorize: force-push to shared branches, push to `main`/`prod`, hook bypass (`--no-verify`), or any non-catch-up edits made during conflict resolution.

If lint/tests fail after conflict resolution → stop and surface; the authorization is conditional on green verify.

## When to invoke

Any variant of: "rebase this onto main", "merge main in", "fix conflicts w/ main", "sync with main", "this branch is behind main", "#XXX merged, catch us up".

**Also** for stacked/chained branches: "catch up the stack", "sync the chain", "PR #A merged, propagate", "update B and C". See [Stacked branches](#stacked-branches) — do NOT dispatch parallel agents across the chain.

## Single-branch flow

1. `git fetch origin`
2. Apply `~/.claude/lib/catch-up-shared.md` against `target = origin/main` — decision script, merge/rebase flow, verify, commit + push (lax).

That's it. Shared file owns the engine.

## Stacked branches

Chain `main <- A <- B <- C`: walk sequentially **from the top**. Each downstream link depends on its parent's resolved state — parallelism is wrong (B can't be caught up until A's new tip exists).

### Algorithm

```bash
git fetch origin
# define chain top→bottom, e.g., parents=(main A B) children=(A B C)
```

For each pair `(parent, child)`:

1. **Drift check**: `git log --oneline origin/<child>..origin/<parent> | wc -l`
   - `0` → skip, move to next link
   - `>0` → catch up this link
2. **Catch up** using shared rules with `target = origin/<parent>`.
3. **Verify** + **commit + push** per shared lax policy.
4. Continue.

### Short-circuit rules

- First link with **no drift** → still descend; lower link may have drifted independently.
- First link with **drift** → catch up, then re-evaluate each subsequent link against its now-updated parent.
- **Conflict at link N** that can't be auto-resolved → stop whole walk, surface to user. Do NOT skip ahead.

### Chain-specific anti-patterns

- Dispatching one agent per link in parallel — they race on fetch/push; B's resolution depends on A's new tip.
- Catching up C directly against `main` — skips A's/B's contributions; re-resolves same conflicts later.
- Force-pushing a middle link without informing downstream — C's merge-base disappears. If a mid-chain rebase is unavoidable, rebase every downstream link too in same session.

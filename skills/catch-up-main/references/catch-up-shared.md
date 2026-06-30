# catch-up shared rules

Common decision/conflict-resolution logic for `catch-up-main`. Skill bodies handle target resolution + stash + push policy; this file is the merge/rebase engine.

## Decision: merge vs rebase

```bash
bash scripts/catch-up-decide.sh <target-ref>   # main | <pr-base>
```

Outputs JSON `{to_absorb, ours, choice, reason}`. Count-based default.

**Override to merge** if any of:
- PR already has review comments / pushed for review → preserve SHAs
- Our branch is a refactor/superset of what target merged → take-ours

Default is conservative (merge unless small+linear).

## Merge flow

```bash
git merge <target> --no-commit --no-ff
git diff --name-only --diff-filter=U    # list conflicts
```

Per conflicted file:

1. Read surrounding context, not just the hunk.
2. **Superset wins** — if our branch refactored the same area, take ours. Target's incremental change is already subsumed.
3. **Additive target wins** — if target added unrelated improvement (better error classification, new header), port into our version.
4. **Cosmetic collisions** (renames, import order) — take whichever reduces reviewer diff noise.

Announce per-file rationale in one line (`take ours — getBalances signature changed`, `port main's 401 detection into our refactored method`).

## Rebase flow

```bash
git rebase <target>
# per conflicting commit: resolve, git add, git rebase --continue
# if resolution gets insane, abort and switch to merge:
git rebase --abort && git merge <target> --no-commit --no-ff
```

## Verify before commit

Stop on first failure, fix, retry:

```bash
<your-package-manager> run lint   # or repo's typecheck (tsc --noEmit)
<your-package-manager> run test   # full suite, not just changed files
```

Multi-package repos: run at affected package root (`apps/backend` etc).

## Commit & push

**Mode: lax** — see `references/commit-push-policy.md`. Catch-up flows are pre-authorized; commit + push without per-turn confirm once lint + tests pass.

```bash
git add <resolved-files>
git commit --no-edit   # default merge message is fine
git push
```

On lint/test fail: stop + surface. Never commit broken merge.

## Anti-patterns

- `git rebase` blindly on 50+ commit branch — replays every conflict per commit.
- `--strategy-option=theirs` wholesale — silently drops our work.
- Deleting untracked files to "clean up" — respect intentionally unstaged changes.
- Skipping lint/tests because "merge is just conflict resolution" — resolutions regularly break types.
- Committing without asking — catch-up has explicit lax override; other skills don't.

## Red flags — pause

- Conflict spans >100 lines in one file → read whole function, don't patch hunk.
- Both sides introduce different function signatures → check callers before picking.
- Target deleted file our branch still modifies → ask user (keep vs delete).

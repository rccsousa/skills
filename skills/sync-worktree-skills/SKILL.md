---
name: sync-worktree-skills
license: MIT
description: Use after `git worktree add` to symlink project `.claude/skills/` (and optionally plans/specs) from the main checkout into the new worktree. Project `.claude/` stays untracked by design, so worktrees miss skills by default. Triggers - "/sync-worktree-skills", "skills missing in worktree", "after git worktree add".
disable-model-invocation: true
---

# sync-worktree-skills

Symlink `.claude/skills/` from the main project checkout into a fresh (or existing) worktree. Project `.claude/` is untracked by design, so worktrees ship without skills unless symlinked.

## Why this exists

Worktrees check out only tracked git files. Project `.claude/` is intentionally untracked → fresh worktrees have no `skills/`, `plans/`, etc. Without a sync step, `/create-pr` and friends are missing inside worktrees — confusion + manual cp / re-creation.

Symlink (vs copy) chosen because:
- Single source of truth — edit in main, all worktrees see it
- No drift / no re-sync ritual
- Skills aren't branch-specific code; sharing across worktrees is correct

## Pipeline

```
detect main checkout → resolve worktree(s) target → symlink skills (and optionally plans/specs) → verify
```

## Arguments

- `$1` (optional) — worktree path. Else current dir if it's a worktree.
- `--all` — sync all worktrees under `.worktrees/` of main checkout
- `--include <skills|plans|specs|settings>` — pick what to symlink (default: skills only)
- `--dry-run` — show what would happen

## Default scope

By default, only `skills/` is symlinked. `plans/`, `specs/`, `settings.json` may carry branch-specific state — opt-in via `--include`.

Never symlink:
- `settings.local.json` (auto-created per worktree, user-private)
- `scheduled_tasks.lock` (runtime state)
- `worktrees/` (Claude internal)

## Steps

### 1. Detect main checkout

```bash
scripts/get-worktree-info.sh   # → {mainPath, worktrees:[{name,path,branch,isMain}]}
```

`.mainPath` is the symlink source root. Shared primitive (also used by
housekeeping) — don't re-parse `git worktree list` by hand.

### 2. Resolve target worktree(s)

- `$1` given → that path
- `--all` → `.worktrees[] | select(.isMain | not) | .path`
- No arg → current working dir; verify it's under main's `.worktrees/`

Halt if:
- Current dir == main checkout (no symlink needed; skills live here)
- Target is not a git worktree

### 3. Compute relative target

For a worktree at `<root>/.worktrees/<name>/`, the symlink path is `<root>/.worktrees/<name>/.claude/skills` with target `../../../.claude/skills` (3 levels up).

Verify by `readlink -f`:

```bash
readlink -f "<worktree>/.claude/skills"  # should resolve to <root>/.claude/skills
```

### 4. Create symlink

```bash
mkdir -p <worktree>/.claude
ln -sfn ../../../.claude/skills <worktree>/.claude/skills
```

`-s` symbolic. `-f` replace existing. `-n` treat existing link as a file (don't follow into target).

Skip with note if already a symlink pointing to the right target.
Refuse + surface if `.claude/skills` already exists as a real directory in the worktree (user copied skills manually; symlinking would clobber).

### 5. Optional includes

If `--include plans` / `--include specs` etc., repeat step 4 for each name.

### 6. Verify + report

```bash
ls -la <worktree>/.claude/
readlink <worktree>/.claude/skills
```

Output:

```
worktree: .worktrees/ofx-status
  ✓ skills → ../../../.claude/skills (linked)
  - plans (skipped, not in --include)
```

## When to invoke

- Right after `git worktree add` (canonical moment)
- When skills appear missing inside a worktree (`/create-pr` not found, etc.)
- After moving a worktree (symlink paths use relative depth — moves break links)

## Halt conditions

- Current dir is main checkout → no-op, halt
- Target dir is not under main's git worktree list → halt (refuse to symlink random dirs)
- `.claude/skills` exists as real dir in target → halt + ask user to move/delete
- Source `<main>/.claude/skills` missing → halt (nothing to link to)

## Out of scope

- Creating the worktree itself (`git worktree add`) → manual
- Removing stale worktrees → `git worktree remove`
- Syncing `.claude/` content across worktrees long-term → not a concern; symlink covers it

## Why not commit + push?

Project `.claude/` stays untracked + user-private by design. Skills are personal workflow tooling, not team-shared conventions. Worktrees solved via symlink, not commit.

## Why not copy?

Copy creates drift — edit a skill in worktree A, worktree B and main don't see it. Forces a re-sync ritual. Symlink = single source of truth, zero maintenance.

Trade-off accepted: a skill edited inside a worktree affects all worktrees + main immediately. For workflow skills (PR gate, interview, request-review) this is correct — they're not branch-specific.

## Future automation

If worktree creation gets wrapped in a skill (e.g., `/new-worktree <branch>`), bake the symlink step in. Until then, `/sync-worktree-skills` is the manual companion to `git worktree add`.

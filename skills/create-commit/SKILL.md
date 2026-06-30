---
name: create-commit
license: MIT
description: >
  Stage changes and create a commit with a one-line Conventional Commits message.
  Groups files by logical change, builds a focused subject, and never adds Claude
  as co-author. Use when ready to commit, after a focused chunk of work, or when
  the user says "commit this", "make a commit", "stage and commit".
---

# Create Commit

Stage + commit w/ Conventional Commits, **oneliner only** (subject line, no body,
no footer). Single-purpose commits, no Claude co-author, hitl by default.

## When to use

- After a focused chunk of work is ready to land
- Inside `one-shot` implement phase (called by worker agents)
- Whenever the user says "commit this" / "make a commit"

Skip if working tree is clean → halt.

## Invocation

```
/create-commit [--all] [--type=<type>] [--scope=<scope>] [--message=<msg>] [--split]
               [--auto --i-understand-the-risk]
```

Flags:

- `--all` — stage all modified + untracked files (default: detect logical group)
- `--type=<type>` — Conventional Commits type (feat/fix/chore/docs/refactor/test/perf/build/ci/revert)
- `--scope=<scope>` — optional scope
- `--message=<msg>` — override derived subject
- `--split` — propose multiple commits if changes span unrelated logical groups
- `--auto` — skip the confirmation gate (see ⚠️ section below). Requires
  `--i-understand-the-risk` as a companion flag. Used by `one-shot --mode=auto`.

Default behaviour: confirmation gate is ON, every commit requires explicit "go".

## Process

1. **Inspect changes.** `git status --porcelain` + `git diff --stat` + `git diff --staged --stat`.
2. **Identify logical groups.** Heuristics:
   - Same top-level dir (e.g. `src/auth/*` + `tests/auth/*`) → one group
   - `package.json` + lockfile → one group
   - `docs/` changes separate from code
   - Unrelated dirs → propose split
3. **If multiple groups + `--split` flag:** propose N commits, walk one at a time.
   Else: bundle all into one commit.
4. **Derive type + scope.**
   - `--type` flag → use it
   - Else: detect from diff (new file in `src/` → `feat`; bug-fix keyword in diff
     → `fix`; only docs → `docs`; tests-only → `test`; etc.)
   - Scope: top-level dir of changed files
5. **Build subject.** Imperative, lowercase, ≤70 chars, no trailing dot. **Oneliner only — no body, no footer.**
6. **Confirmation gate** (skipped only when `--auto --i-understand-the-risk` both present + gate preconditions hold; see below).
7. **Stage + commit.** `git add <files>` → `git commit -m <subject>`.
8. **Verify.** `git log -1 --format="%H %s"` → return SHA + subject. In `--auto`, also append a line to `.claude/auto-mode.log`.

## Confirmation gate

Default ON: surface proposed commit, wait for "go" / "yes" / "commit" before staging
+ committing.

Format:

```
proposed commit:

  feat(auth): rotate refresh tokens on use

files (3):
  src/auth/refresh.ts        +42 -8
  src/auth/handler.ts        +12 -3
  tests/auth/refresh_test.ts +88 -0

  [g] go
  [e] edit message
  [s] split (propose multiple commits)
  [c] cancel
```

### ⚠️ `--auto` (gate skip)

`--auto --i-understand-the-risk` lifts the per-commit gate. Used by
`one-shot --mode=auto` to keep the cascade unattended.

**Preconditions — all must hold, else refuse + halt:**

1. Both flags present: `--auto` AND `--i-understand-the-risk`. No env var, no
   default. The risk-ack flag has no shorthand.
2. `.claude/auto-mode-disabled` not present at repo root.
3. `~/.claude/auto-mode-disabled` not present globally.
4. Current branch != repo default branch (no auto commit on `main` / `master`).
5. No `--amend` flag (auto + amend is never allowed).
6. Pre-commit hooks present + would run normally (`--no-verify` is always
   refused, even in auto).

If any fails → halt with the specific reason. Do not silently downgrade.

**In auto mode:**

- Surface a one-line audit (`auto-commit: feat(auth): ... [3 files]`) before
  staging, but do not wait for input.
- Append a line to `.claude/auto-mode.log`:
  `2026-05-21T14:32:18Z create-commit <sha> <subject>`.
- Hard caps still apply: no `--no-verify`, no `--amend`, no co-author injection,
  no identity override. All "Hard rules" below remain in force.

## Message format

```
<type>(<scope>): <subject>
```

**Oneliner only.** No body, no footer, no `BREAKING CHANGE:`, no `Closes #N`.
If a footer feels load-bearing (breaking change, issue link), put it in the PR
description instead — the commit stays a single line.

**Hard rules** (apply always, no override):

- **Use the caller's git identity** (`user.name` / `user.email` from local git config).
  Never set `--author`, never export `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL`, never
  inject any marketplace-owner identity into the commit.
- Never add `Co-Authored-By: Claude` (or any Claude variant)
- Never add `🤖 Generated with Claude Code` (or similar AI-source markers)
- Never pass `-m` twice — single subject line only
- Never use `--no-verify` (don't bypass hooks)
- Never use `--amend` unless user explicitly asks (creates a new commit instead)

## Type detection heuristics

| Diff signal                                              | Type      |
|----------------------------------------------------------|-----------|
| New file in `src/` / `lib/` / `app/`                     | feat      |
| `fix`, `bug`, `crash`, `regression` keyword in changes   | fix       |
| Only files in `docs/` / `*.md`                           | docs      |
| Only files in `tests/` / `*_test.*` / `*.test.*`         | test      |
| Only formatting / import-order changes                   | chore     |
| Function renamed without behaviour change                | refactor  |
| Bench / latency / perf keyword in changes                | perf      |
| `Dockerfile`, `package.json` deps, build config          | build     |
| `.github/workflows/`, CI config                          | ci        |

Multiple signals → pick the most specific. Ambiguous → ask user.

## Split detection

Propose `--split` when changes touch unrelated areas:

- `src/auth/` + `src/billing/` (no shared call site)
- `src/` + `docs/` (mixing code + doc updates)
- bug fix + unrelated refactor in same diff

Propose order: smallest blast-radius first (docs → tests → fix → feat → refactor).

User accepts → walk one commit at a time, with the confirmation gate per commit.

## Halt conditions

- Working tree clean → halt: "nothing to commit"
- On detached HEAD → halt: "checkout a branch first"
- Pre-commit hook fails → halt w/ hook output; do NOT bypass w/ `--no-verify`
- User cancels at gate → halt cleanly, leave staging area as-is

## Output style — caveman ultra (under-the-hood)

Applies to: commit subject, surface text to user during gate.

Does NOT apply to: file paths, identifiers, error messages, SHAs.

**Rules:**

- Subject: imperative verb + object, fragments OK, ≤70 chars
- Drop articles, filler
- Short synonyms (DB / auth / fn / req / res / impl)

Examples:

- Normal: `feat(auth): add a check to validate refresh token timestamps within a 5-minute window`
- Caveman ultra: `feat(auth): bound refresh token replay window to 5min`

- Normal: `fix(api): the error in the handler was being silently swallowed`
- Caveman ultra: `fix(api): rethrow swallowed err in handler`

## Out of scope

- Pushing the commit → `git push` (separate step; `/create-pr` handles it)
- Opening a PR → `/create-pr`
- Amending a previous commit → user-driven only, never automatic
- Force-push, rebase, merge → out of scope

## Why this skill exists

Conventional Commits + no co-author + hitl confirmation are repeated invariants
across the plugin. Centralising them here means `/one-shot`, `/code-fix`, and
worker agents all produce uniform commits without re-implementing the rules.

The confirmation gate defaults to ON. The `--auto` escape exists for
`one-shot --mode=auto`, gated behind an explicit risk-ack flag and the
repo/global `auto-mode-disabled` veto. The invoker owns the call to lift the
gate. Hard caps — no `--no-verify`, no `--amend`, no co-author injection —
apply in every mode.

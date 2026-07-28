---
name: land
description: >
  Drive an open PR all the way to merged — review cascade, autofix, undraft, verify,
  merge — behind a deterministic core-path gate that refuses to auto-merge anything
  touching migrations, CI, auth, lockfiles, or repo-declared core paths. This is the
  one skill allowed to run `gh pr merge` unattended; /one-shot and /drive-to-mergeable
  both stop short of merge on purpose. Use when the user says "/land", "land this PR",
  "take it all the way", or as nightshift's phase 3. Merging by hand is /merge-pr.
disable-model-invocation: true
metadata:
  version: 0.1.0
---

# Land

**This is the global fallback.** A repo with its own `.claude/skills/land/`
shadows this one — a project-local version can be richer (e.g. Copilot +
CodeRabbit as the merge gate, with merge pre-authorised for that repo
specifically). Where a project-local `/land` exists, that one wins and this file
is not in play. Don't reconcile them; they're for different situations.

`/drive-to-mergeable` stops at the human merge gate. `/merge-pr` is that human
pressing the button. **`/land` is the button pressed by a machine** — so the gate
that replaces the human has to be deterministic, narrow, and unarguable.

Thin glue. Owns exactly two things: the **core gate** and the **bounds**. Everything
else is existing skills.

## Invocation

```
/land [PR#] [--dry-run]
```

`PR#` optional — defaults to the current branch's PR. `--dry-run` runs the gate and
reports the verdict without touching the PR.

## Pipeline

```
resolve PR → CORE GATE → /drive-to-mergeable → gh pr ready → /pr-ready → gh pr merge
                 ↓ fail
          label nightshift-noland, comment reason, STOP
```

## 1. Core gate — deterministic, runs first

Before any work. A PR whose diff touches **any** denied path does not land, full
stop. No judgment, no override at runtime, no "but it's only a small change".

```bash
bash ~/.claude/skills/land/lib/core-gate.sh <PR#>
```

Exits `0` (pass) or `1` (fail, prints the offending paths). It reads:

**Universal denies — always applied, not configurable:**

```
**/migrations/**   db/schema.*   **/schema.rb   priv/repo/migrations/**
.github/**   Dockerfile*   docker-compose*   fly.toml   *.tf   *.tfvars
package-lock.json  yarn.lock  pnpm-lock.yaml  mix.lock  Gemfile.lock  go.sum  Cargo.lock
**/auth/**   **/permissions/**   **/*polic*   **/*authoriz*
.env*   **/secrets*   **/*credential*
CODEOWNERS   CLAUDE.md   AGENTS.md   .claude/**
```

**Repo denies** — `core_paths` in `.nightshift/config.json` at repo root:

```json
{ "core_paths": ["lib/myapp/billing/**", "src/core/pricing/**"] }
```

Missing config is not an error — universal denies still apply. Say so in the report.

On fail: `gh pr edit <n> --add-label nightshift-noland`, comment the offending
paths in one line, stop. The PR stays a draft for a human. That is a **success**
outcome for this skill, not a failure — report it as such.

## 2. Drive to mergeable

Run `/drive-to-mergeable <PR#>`. It handles the internal review, the external bot,
finding triage, surgical autofix with a regression test, red CI, and thread
resolution. Do not duplicate any of that here.

**Bounds — exceeded means stop and leave the PR open, never spin:**

| Bound | Value | On breach |
|-------|-------|-----------|
| autofix cycles | 2 | stop, label `nightshift-noland`, reason `unresolved after 2 fix cycles` |
| CI poll | 30 min | stop, reason `ci-timeout` |
| rebase conflict | — | stop immediately, reason `conflict with base` |
| new must-fix after a fix cycle | — | stop, reason `review not converging` |

Never retry past a bound. Never invent a new strategy. A human picks it up.

## 3. Undraft + verify

```bash
gh pr ready <n>
```

Then `/pr-ready <n>`. If it reports BLOCKED, stop — label `nightshift-noland` with
the block reason. `/pr-ready` is the last gate and it is not advisory.

## 4. Merge

```bash
gh pr merge <n> --squash --delete-branch
```

Squash by default. `--method` from `.nightshift/config.json` `merge_method` if set.

This is the only place in the whole skill set where `gh pr merge` runs without a
human. It is reachable only through steps 1–3.

## 5. Report

```
LANDED <n> <sha>
```

or

```
NOLAND <n> <reason>
```

One machine line, last. nightshift's driver greps for it.

## Hard caps — never, in any mode

- `git push --force` / `--force-with-lease`
- `git commit --no-verify` / `--amend`
- merging into a branch other than the PR's declared base
- merging a PR opened by anyone other than the authenticated user
- editing the core gate's universal deny-list to make a PR pass
- proceeding when `.claude/auto-mode-disabled` or `~/.claude/auto-mode-disabled` exists

## Standalone use

`/land 441` works on its own — useful for a PR you've already reviewed and want
driven the rest of the way. The core gate still applies. If you want to merge
something the gate refuses, that's `/merge-pr`, with you in the loop. Correct
division: the gate exists to stop a *machine*, not to stop you.

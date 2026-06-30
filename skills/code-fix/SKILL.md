---
name: code-fix
license: MIT
description: >
  Apply fixes from a code-review findings packet. Always fixes must-fix +
  should-fix, fixes consider items only when sensical (defers judgement-call
  ones), applies fixes, commits via /create-commit. Works on a local branch (no PR yet) or
  against an open PR — driven by the packet's `source` field. Three modes
  (ack, approve, auto) control how much the skill does after committing —
  `auto` pushes + replies on threads (PR mode) or just commits locally (local
  mode), gated behind a risk-ack flag. Use as the receive side of one-shot's
  review cascade, or standalone when you have a review to address.
---

# Code Fix

Receive side of the one-shot review cascade. Consumes a findings packet
(from `/code-review` or hand-written) and applies fixes for must-fix + should-fix
items (always) plus sensical consider items as commits. Works in two modes mirroring
`/code-review`:

- **Local mode** (`source: local` in packet) — branch has no PR yet. Skill
  commits fixes locally. `auto` mode does NOT push or open a PR — that's the
  next phase (`/create-pr`). Thread replies skipped (no threads to reply to).
- **PR mode** (`source: pr` in packet) — branch has an open PR. `auto` mode
  pushes + replies on resolved threads.

Modes `ack` + `approve` always stop at "fixes committed".

## When to use

- Right after `/code-review` produced a findings packet (cascade flow)
- Addressing a human reviewer's comments on a PR
- Inside `one-shot` fix phase

Skip if the review packet is empty (no must-fix, no should-fix, no consider).

## Invocation

```
/code-fix [PR-number] --findings=<path-or-inline> [--mode=ack|approve|auto]
        [--i-understand-the-risk]
        [--max-parallel=N] [--no-parallel]
```

Flags:

- `[PR-number]` (positional, optional) — overrides packet's `pr` field. Omit
  for local-mode packets (no PR yet).
- `--findings=<path>` — path to YAML packet (from `/code-review` or hand-written)
- `--findings-inline` — packet pasted as next message
- `--mode=ack` — fix all, surface diff for user OK before handing back (default, one-shot hitl)
- `--mode=approve` — per-thread "fix / defer / followup" before applying (one-shot grill)
- `--mode=auto` — fix + commit (+ push + reply on threads in PR mode), no user
  gate. Requires `--i-understand-the-risk`. Used by `one-shot --mode=auto`.
  See ⚠️ section.
- `--max-parallel=N` — cap fix-worker fan-out (default: unbounded — one worker
  per file-partition of findings spawns in parallel)
- `--no-parallel` — disable fan-out, run a single fix agent serially over all
  findings (legacy mode)

Mode (local vs PR) is read from the packet's `source` field, not from a flag —
review and fix always agree on the diff source.

## Process

1. **Load findings packet.** Validate shape (must_fix, should_fix, consider, nit, merge_blocking keys).
2. **Scope = must-fix + should-fix always, consider only when sensical.** must-fix
   + should-fix are mandatory — every item gets fixed. consider is judgement-call:
   fix the ones with a clear, low-risk fix (the "sensical" ones); defer the noisy
   / arguable ones (record under `deferred` in the return payload with a one-line
   reason). Skip nits unless trivial (1-line / pure rename).
   - **Sensical consider** = fix is obvious, in-scope, low-risk (e.g. extract a
     named const for a magic number, add missing docstring, finish an
     inconsistent rename). Just do it.
   - **Non-sensical consider** = fix needs a judgement call, would balloon the
     diff, or is arguable taste. Defer, don't guess.
3. **Partition findings by file.** Each file becomes one partition; partitions are disjoint by construction. Nits attached to a partition's files ride along if trivial.
4. **Fan out fix workers in parallel** (default; serial if `--no-parallel`). One worker per partition, each in its own `isolation: "worktree"`. Default each worker to Sonnet; escalate hard partitions to Opus (see **Worker model** below). Mode `approve` falls back to serial (per-finding user input precludes parallelism). All workers dispatched in a single message.
   - Each worker:
     - Cd into its worktree (forked from head branch)
     - Read its scoped findings (file, line, summary, why, fix_hint)
     - Apply fixes in code
     - Stage + commit via `/create-commit` (one commit per logical fix). In `--mode=auto`, pass `--auto --i-understand-the-risk` through.
     - Run scoped local tests (best-effort, fast tests only)
     - Return: worktree path, branch name, commit SHAs, scoped-tests status
5. **Aggregate.** Orchestrator cherry-picks each worker's commits onto the head branch in deterministic order (file path → sha). Conflicts shouldn't occur (disjoint partitions); if one fires → halt + surface.
6. **Verify aggregated branch.** Run full test suite once on the head branch. Authoritative pass/fail.
7. **Surface diff + commit list to user.**
   - `ack`: await explicit ack.
   - `approve`: no extra ack — already approved per-finding (serial-only mode).
   - `auto`: no ack, log to `.claude/auto-mode.log` instead.
8. **Hand back.**
   - `ack` / `approve`: return payload with commit SHAs, suggested thread
     replies (PR mode only), suggested follow-up issues. Skill does NOT push,
     does NOT reply, does NOT file. User-driven next steps.
   - `auto` + **local mode**: commits only — no push, no PR open, no thread
     replies. Suggested follow-ups stay in payload. Next phase
     (`/create-pr --auto`) handles push + PR open.
   - `auto` + **PR mode**: `git push`, post per-thread replies via
     `gh pr review-comment`, append audit lines, then return payload. Never
     `gh pr merge`. Never `gh issue create` (suggested followups stay in payload).

## Parallel fan-out

Default = fan out flat. One fix worker per file-partition of findings, no cap.
Workers run in isolated worktrees so they can't trip over each other's staging
area or partially-applied commits.

```
        [orchestrator]
              │
    load + partition findings by file
              │
   ┌────┬────┬┴───┬────┬────┐
   ▼    ▼    ▼    ▼    ▼    ▼
  w1   w2   w3   w4   w5   wN   (each in own worktree)
   │    │    │    │    │    │
   └────┴────┴────┴────┴────┘
              │
   cherry-pick all commits onto head branch
              │
   full test suite once on head
              │
       hand back / push
```

**Throttles:**

- `--max-parallel=N` — cap concurrent workers at N (default = unbounded).
- `--no-parallel` — single fix agent processes all findings serially in the
  current worktree. Legacy mode. Useful when changes have hidden cross-file
  coupling and you don't trust file partitioning.

**Mode interaction:**

- `ack` + `auto` → parallel by default
- `approve` → **always serial** (per-finding user prompts can't fan out)

**Worker model (not sonnet-locked):**

Workers are NOT hard-pinned to Sonnet. Default each fix worker to Sonnet, but
escalate a worker to **Opus** when its partition is hard — pass `model: "opus"`
to that worker's Agent call. Escalate when the partition contains:

- any **must-fix** finding (security / race / contract break — high blast radius), or
- a **should-fix** finding whose `fix_hint` implies an architectural / multi-file
  decision rather than a mechanical edit, or
- a `needs-opus` tag carried through from the plan / one-shot.

Mixed packets fan out heterogeneously: the hard partitions go to Opus, the rest
stay on Sonnet, all in the same dispatch message. Pure-consider / pure-nit
partitions never escalate. `--no-parallel` serial mode picks one model for the
whole run — Opus if any must-fix present, else Sonnet.

**Why partition by file:** the only way to commit independently without
conflict is to write to disjoint paths. Findings that share a file always
land in the same worker so the in-file ordering stays controlled. Cross-file
findings are independent by construction — different worker, different
worktree, separate commit, clean cherry-pick.

**Failure handling:**

- Any worker fails to apply → halt the entire phase, surface which partition
  failed + why. No partial commit set lands.
- Cherry-pick conflict (rare; would mean partitions weren't truly disjoint —
  e.g. a worker touched a file outside its scope) → halt + name conflicting
  files.
- Full-suite tests red after aggregation → halt + surface failing tests; do
  not push (auto) or hand back as ready (ack).

## Per-finding decision (mode=approve)

For each finding, present:

```
[MUST-FIX] src/auth/refresh.ts:42
replay window unbounded
why: token timestamp not checked → replay possible
fix hint: enforce 5min window per plan §4

  [f] fix now
  [d] defer (record in return payload, user decides later)
  [u] follow-up (add to suggested_followups for user to file)
  [s] skip (surface as ignored, no action)
```

Wait for input per finding. No batching. None of these options touch GitHub —
they only shape the return payload.

## Out-of-scope handling

A finding is out-of-scope when:

- Fix balloons diff past plan-implied size
- Fix touches subsystems outside PR scope
- Fix requires architectural decision not in plan

For each: surface as a suggested follow-up issue in the return payload — title,
excerpt, link back to PR. User decides whether to file via `gh issue create`.

Never silently skip. Either fix, suggest-followup, or explicit defer w/ reason.

## Halt conditions

- Findings packet malformed → halt: "packet missing required keys: <list>"
- PR mode + branch already merged → halt: "PR closed, nothing to fix"
- PR mode + branch behind base + auto-rebase fails → halt: "rebase needed, conflicts in <files>"
- Local mode + branch == base → halt: "on base branch, refuse to commit fixes here"
- Tests fail after fix → halt: "tests red after fix, see <output>"
- More than 3 must-fix findings → halt: "too many must-fix — recommend split into followup PR"

## Push policy

- `ack` / `approve` (any source): skill does NOT push. Commits stay local.
  User runs `git push` (or `/create-pr` if branch isn't pushed yet) after
  reviewing.
- `auto` + **local mode**: skill does NOT push. Commits stay local. The
  next phase of the orchestrator (`/create-pr --auto`) handles push + PR open.
- `auto` + **PR mode**: skill pushes via `git push origin <branch>` (no
  `--force`, no `--force-with-lease`). If remote has diverged → halt, no force.

## ⚠️ `--mode=auto` (gate)

`--mode=auto --i-understand-the-risk` lets the skill push + reply on GitHub
threads without user prompts. Used by `one-shot --mode=auto`.

**Preconditions — all must hold, else refuse + halt:**

1. Both flags present: `--mode=auto` AND `--i-understand-the-risk`.
2. `.claude/auto-mode-disabled` not present at repo root.
3. `~/.claude/auto-mode-disabled` not present globally.
4. PR mode only — PR is in draft state (no auto-pushing to PRs already in
   human review). Local mode skips this check (no PR exists yet).
5. Current branch != base.
6. PR mode only — `gh` authed as a single known user.
7. No more than 3 must-fix findings (matches existing halt cap — too many
   must-fix → split, never auto-fix).

In `auto` mode:

- Per-commit pass-through: `/create-commit --auto --i-understand-the-risk`.
- Push (PR mode only): `git push origin <branch>` (refuse on conflict; never
  force). Local mode skips push — the orchestrator runs `/create-pr` next.
- Thread reply (PR mode only): `gh pr review-comment reply <comment-id>
  --body <reply>` for each fixed finding. Never `gh api graphql
  resolveReviewThread` (resolving threads stays user-driven — Claude posts
  the reply, the user resolves). Local mode skips thread replies (no
  threads exist).
- Followups: stay in return payload as suggestions only. Never `gh issue
  create`. Never `gh pr merge`.
- Audit log: append one line per commit (+ per push + per reply in PR mode)
  to `.claude/auto-mode.log`.

## Return payload

YAML, caveman-ultra strings. In `auto` mode, `suggested_thread_replies` is
replaced with `threads_replied` (replies already posted).

```yaml
source: pr                 # local | pr (mirrors packet)
pr: 1234                   # null in local mode
url: https://github.com/org/repo/pull/1234  # null in local mode
mode: auto
pushed: true               # false in ack/approve and in auto+local
commits:
  - sha: abc1234
    msg: "fix(auth): bound replay window to 5min"
  - sha: def5678
    msg: "fix(auth): rethrow refresh err → 401"
threads_replied:           # auto+PR mode only — empty in local mode
  - finding: src/auth/refresh.ts:42
    reply: "replay window bounded to 5min. fixed in abc1234."
  - finding: src/auth/handler.ts:88
    reply: "rethrow → 401 on refresh fail. fixed in def5678."
suggested_thread_replies: []  # ack/approve + PR: populated; local: empty
suggested_followups:       # always suggestions — never filed automatically
  - title: "rate-limit refresh endpoint"
    summary: "token-bucket per user; out of scope"
deferred:                  # non-sensical yellows skipped w/ reason
  - finding: src/auth/store.ts:23
    severity: consider
    reason: "magic-number extract = taste call, no clear name → defer to user"
tests_status: green
ready_for_pr: true         # local mode: fixes done, next phase opens PR
ready_to_merge: true       # PR mode: pushed + threads replied; user still merges
```

## Output style — caveman ultra (under-the-hood)

Applies to: commit messages, suggested thread replies, suggested follow-up
issue bodies, summary surfaced to user, return payload strings.

Does NOT apply to: code (verbatim), file paths, line numbers, identifiers,
error strings, halt messages.

**Rules** (same as code-review):

- Drop articles, filler
- Fragments OK
- Short synonyms (DB / auth / fn / req / res / impl)
- Arrows for causality (X → Y)
- One word when one word suffices

Example suggested thread reply (user copies to GH):

- Normal: "I have added validation for the replay window as you suggested."
- Caveman ultra: "replay window bounded to 5min. fixed in <sha>."

## Out of scope

- Producing the review itself → `/code-review`
- Opening the PR → `/create-pr`
- Making the commit (delegated) → `/create-commit`
- Pushing fixes (ack/approve modes) → user runs `git push` after reviewing
- Resolving GitHub threads (ALL modes, including auto) → user resolves manually
- Filing follow-up issues (ALL modes, including auto) → user runs
  `gh issue create` from the suggested list
- Merging the PR (ALL modes, including auto, hard cap) → user merges manually

## Why this skill exists

Without a structured cascade, the fix step needs full re-briefing (read review,
re-read code, classify, fix). With a findings packet, the fix agent skips
re-discovery and goes straight to applying.

The `--mode` flag mirrors `one-shot` so the orchestrator can pass through
its current mode verbatim:

- one-shot hitl → `--mode=ack`
- one-shot grill → `--mode=approve`
- one-shot auto → `--mode=auto --i-understand-the-risk`

Auto mode exists for `one-shot --mode=auto`, gated by the risk-ack flag
and the `auto-mode-disabled` veto, and hard-capped against merge, force-push,
thread resolution, and issue filing. The invoker owns the call. Default modes
(`ack`, `approve`) stop at "fixes committed locally" so push + GitHub writes
pass through the user.

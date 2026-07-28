---
name: nightshift
description: >
  Unattended overnight drain of a GitHub issue queue. Enriches every issue labelled
  `nightshift` into an agent-pickup-ready brief, then emits a detached bash driver
  that runs one headless `/one-shot` session per issue in its own worktree — 3
  concurrent — opening a draft PR each, and flags which PRs pass the core-path gate
  so morning review knows what's safe to land. Bare `/nightshift` with no arguments
  is the intended invocation: it reports the last finished run, then starts
  tonight's. Use when the user says "/nightshift", "drain the queue overnight",
  "work the backlog while I sleep".
disable-model-invocation: true
metadata:
  version: 0.1.0
---

# Nightshift

`/one-shot` ships one feature. **Nightshift runs one-shot against a whole queue,
unattended, and hands you a morning report.**

You type `/nightshift`. Nothing else. Everything is resolved from repo state and
`.nightshift/config.json`.

```
/nightshift
  ├─ 0. state check    report last finished run (if unreported), then continue
  ├─ 1. pre-flight     resolve repo/base/queue/config — halt loudly, never ask
  ├─ 2. banner         print the plan, 10s abort window, auto-proceed
  ├─ 3. enrich         parallel headless /issue-enriching per issue     [you drive]
  ├─ 4. emit driver    write <run-dir>/run.sh from the template
  └─ 5. nohup & return session free; bash owns the night                [bash drives]
```

**Your job ends at step 5.** Do not hold the loop. Do not poll. Do not wait.

## What it does not do

It does not merge. The driver opens draft PRs and labels which ones clear the
core-path gate; you merge with `/land <PR#>` in the morning, or by hand. Every PR
still meets a human before it reaches the base branch.

## Why the driver is bash

A Claude session holding a 6-hour loop dies with the terminal, accumulates context
all night, and burns tokens sitting idle. The emitted `run.sh` survives terminal
close, is restartable, and costs nothing while it waits. The price is that mid-run
control flow is dumb — which is why every decision needing judgment (enrichment,
verdicts) happens in step 3, before the driver starts.

## Context isolation

Each issue gets a **brand-new top-level `claude -p` session** — its own full context
window, its own budget, running `/one-shot` at full fan-out. Nothing leaks between
issues; nothing accumulates in yours. That's the "clear between tasks" property,
achieved by never accumulating in the first place.

## Permissions — explicit, not blanket

Sessions run `--permission-mode dontAsk` with `--settings <run-dir>/perms.drain.json`
(copied from `lib/perms.drain.json`). That file **denies** `gh pr merge`, force-push,
`--no-verify`, `--amend`, `reset --hard`, publish/release commands, reads of `.env*`
and `**/secrets/**`, and edits to `.claude/**`, `CLAUDE.md`, `.github/**`.

Never use a blanket permission-skip flag. The deny-list is the point: an unattended
session should be *more* constrained than an attended one, not less.

## Budget discipline — the window is real

Three concurrent `/one-shot` sessions, each fanning out internally, will exhaust a
5-hour usage window. Two rules, and they cut in **both** directions.

**Act on a percentage. Never on a raw token count.** A number of tokens is a
numerator — on its own it means nothing. "4.8 million" sounds enormous and can be
30% of the window. Parking early is not conservatism; it wastes the run you were
given. Killing agents mid-task wastes more. Neither is the safe default, which is
why you measure instead of guessing.

**If you don't know the percentage, ask — at pre-flight, while the user is still
there.** They can read it off `/status`; you cannot. One question, before the
banner, costs nothing:

- ≥60% used → say so and recommend a smaller queue tonight, or tomorrow.
- ≥80% used → refuse to start. A run that parks in its first hour is worse than
  no run.
- Unknown and the user is gone → start, and rely on the reactive backstop below.
  Do **not** infer a threshold from magnitude.

**The reactive backstop is the honest signal.** A session killed by the limit is
telling you the truth that no estimate can. The driver greps each session log for
limit errors and, on a hit, **parks the whole run immediately** — never retries
into the wall. The issue goes back to `nightshift`, remaining queue keeps its
label, and `REPORT.md` says `PARKED`. Re-running `/nightshift` resumes.

This is a floor, not a ceiling: it cannot see Claude Code on another machine,
claude.ai, or direct API use. If you work across machines, widen the margin by
asking — not by inventing a number.

## Machine discipline — memory kills runs, not CPU

Several fan-out sessions on one box means swap, and swap means OOM-killed agents
holding uncommitted work.

- `await_headroom` blocks before each dispatch until free RAM clears
  `min_free_mb` (default 2048), bounded at 30 min then dispatches anyway rather
  than stalling the run forever.
- Sessions get `--max-parallel=2`. One-shot's default is unbounded "crazy mode",
  which is correct when it owns the machine and wrong when three copies of it
  don't.
- Sessions are told to have subagents run **scoped checks on files they own,
  never the full suite** — five agents each running every test is five copies of
  the same work, and enough memory pressure to kill the run. The full suite runs
  once, at the end of each one-shot.
- Other `/nightshift` and interactive sessions compete for the same RAM. Dispatch
  fewer slots on a contended box.

## Assume every session will be killed

Limits, OOM, closed laptops. Sessions are instructed to **commit locally whenever
the tree is coherent**, not only at the end — a local commit already survives a
killed agent and costs no CI.

A commit of unverified work is fine **if the message says so plainly**. A commit
that implies verification which never happened is not. `REPORT.md` prints the
`git log --grep` that finds them.

Failed issues keep their worktree at `.worktrees/ns-<n>` for exactly this reason.

## Label state machine — GitHub is the state store

The **nomination** label is `queue_label` from config — default `nightshift`, but
set it to whatever the repo already uses for this — many repos already have a
`ready-for-agent` or `agent-ready` label meaning exactly this. Don't make a repo
maintain two labels that mean the same thing. Everything downstream is
nightshift's own machinery and stays prefixed.

```
<queue_label>         you nominated it; not yet enriched
nightshift-ready      enriched + grounded; safe to one-shot
nightshift-blocked    enrich verdict = defer / not-a-bug / investigation
nightshift-done       draft PR opened, PR link commented on the issue
nightshift-failed     one-shot halted; reason + log tail commented
nightshift-landable   PR cleared the core gate — safe to /land by hand
nightshift-noland     PR touches a core path — needs a real review
```

No local queue file. State survives reboot, is visible to teammates, re-running is
idempotent. Create missing labels on first run (`gh label list` → `gh label create`).

## Step 0 — state check

Look at `.nightshift/`. Newest dated run dir with `.finished` but no `.reported`:
print its `REPORT.md` verbatim, `touch .reported`, then continue to pre-flight. A
run dir with no `.finished` and a live driver means a run is **in flight** — print
status from the ledger and stop. Never start a second run.

## Step 1 — pre-flight (never asks; halts with a reason)

| Condition | Action |
|-----------|--------|
| no issues carrying `queue_label` | print "nothing to do", exit 0 |
| current branch is main/master/repo default | refuse — nightshift branches off it, it can't be it |
| `.claude/auto-mode-disabled` or `~/.claude/auto-mode-disabled` exists | refuse (inherited from `/one-shot`) |
| `gh` not authed, or ambiguous identity | refuse |
| run already in flight | report status, refuse |

Resolve: repo (`gh repo view`), base branch (config `base`, else repo default),
slots (config `max_slots`, else 3), headroom (config `min_free_mb`, else 2048),
nomination label (config `queue_label`, else `nightshift`), run dir
`.nightshift/$(date +%F)`.

**Create the machinery labels now, before anything else runs.** Sessions cannot
create them — see the permission ceiling below — so a missing label makes the
enrich phase fail with `ENRICH-FAILED <n> label-...-missing`:

```bash
gh label create nightshift-ready    --color 0E8A16 --description "Nightshift: enriched + grounded, safe to one-shot"
gh label create nightshift-blocked  --color FBCA04 --description "Nightshift: needs a human decision"
gh label create nightshift-done     --color 1D76DB --description "Nightshift: draft PR opened"
gh label create nightshift-failed   --color B60205 --description "Nightshift: session halted"
gh label create nightshift-landable --color C2E0C6 --description "Nightshift: diff avoids core paths (NOT reviewed)"
gh label create nightshift-noland   --color D93F0B --description "Nightshift: touches a core path, needs real review"
```

Already-exists errors are fine; ignore them.

**Permission ceiling — `dontAsk` denies, it does not prompt.** Anything not in
the repo's `permissions.allow` is refused outright, silently, with no human to
ask. The repo's allow-list is therefore the hard ceiling on what a night can do.
Check it at pre-flight and say in the banner if it looks too narrow to run
`/one-shot` — a repo allowing `Bash(gh issue *)` but not the test runner will
fail every issue in the same way and trip the breaker.

**Only open issues.** Select with `--state open`, and note the driver re-checks
state at dispatch — hours pass between enrichment and the session that builds it,
and an issue can be closed or claimed in that window.

**Check for project-local skills.** Both scopes load, and a project-local skill
wins on a name clash — so a repo with its own `.claude/skills/one-shot/` means
drain sessions run *that* one, not the one you read. Confirm it accepts
`--mode=auto` and `--max-parallel`. Skills that exist only globally still resolve
normally; nothing needs copying in.

If `.claude/skills/` is tracked in the repo, worktrees inherit it. If it's
gitignored, worktrees get nothing — check before relying on a project-local skill
inside a drain session.

Then ask the usage-window question (see **Budget discipline**) — this is the last
moment a human is present.

`.nightshift/` must be gitignored — add it if it isn't.

**Never treat silence as approval.** If you asked something at pre-flight and got
no reply, do not pick for them and do not start. Say you're blocked and stop. The
autonomy this skill was invoked with covers proceeding through *the work* — it
does not cover self-answering the questions you raised before the work began.

## Step 2 — banner

One block, then start. No question, no blocking prompt — Ctrl-C is the abort.

```
NIGHTSHIFT — unattended queue drain

repo:      <owner/name>          base: <base>
queue:     <N> issues labelled `nightshift`
phase 1:   enrich all <N> (parallel)
phase 2:   drain every `ready` — no cap, <slots> concurrent worktrees
per issue: /one-shot --mode=auto --i-understand-the-risk
phase 3:   core-gate scan — labels landable/noland. NO merging.
breaker:   halt after 3 consecutive failures
logs:      <run-dir>/

starting in 10s — Ctrl-C to abort
```

## Step 3 — enrich (you drive this, in-session)

For every nominated issue, one headless session, ~5 concurrent:

```bash
claude -p --permission-mode dontAsk --settings <run-dir>/perms.drain.json \
  "/issue-enriching <n>" > <run-dir>/<n>.enrich.log 2>&1
```

Cheap and short. Grep each log's last `ENRICHED <n> <verdict> <label>` /
`ENRICH-FAILED <n> <reason>` line — that's all you read. Never read the transcripts.

After this phase you know the **real** queue size before a single expensive session
runs. Print one line: `enriched: X ready / Y blocked / Z failed`.

Only `nightshift-ready` issues go into the driver.

## Step 4 — emit the driver

Copy `lib/perms.drain.json` into the run dir. Read `lib/run.sh.tmpl`, substitute:

| Placeholder | Value |
|---|---|
| `{{RUN_DIR}}` | absolute run dir |
| `{{REPO_ROOT}}` | `git rev-parse --show-toplevel` |
| `{{BASE}}` | base branch |
| `{{SLOTS}}` | concurrent drain sessions |
| `{{MIN_FREE_MB}}` | RAM headroom required before dispatching |
| `{{QUEUE_LABEL}}` | nomination label — parked issues are returned to it |
| `{{LAND}}` | `true` to run the phase-3 gate scan, else `false` |
| `{{ISSUES}}` | space-separated `nightshift-ready` numbers |

Write to `<run-dir>/run.sh`, `chmod +x`, `touch <run-dir>/ledger.tsv`.

The template implements: xargs slot pool (no `wait -n` — macOS bash is 3.2),
worktree per issue, the `/verify` mutex injected via `--append-system-prompt`,
ledger append under its own lock, the circuit breaker, the phase-3 gate scan, and
`REPORT.md`.

## Step 5 — launch and return

```bash
nohup bash <run-dir>/run.sh > <run-dir>/nohup.log 2>&1 &
disown
```

Print the run dir and the PID. **Then stop.** Do not tail the log, do not poll, do
not schedule a wakeup, do not report results. The next `/nightshift` does that.

## Runtime behaviour (in the driver, for reference)

- **Concurrency**: `slots` worktrees at `.worktrees/ns-<n>`, branch
  `nightshift/issue-<n>` off base. Removed on success, **kept on failure** for
  post-mortem.
- **Verify mutex**: `/verify` builds and *runs the app*, twice per issue, and in
  auto mode a failure is a hard HALT. Concurrent dev servers collide on ports, so
  one session verifies at a time — `.nightshift/verify.lock`, atomic `mkdir` (no
  `flock` on macOS), 20-minute TTL so a dead session can't deadlock the run.
  Implement/review/fix stay fully parallel.
- **Failures isolate**: a halted issue is labelled, commented with the log tail,
  frees its slot. The run continues.
- **Circuit breaker**: 3 consecutive failures with no success between = systemic
  (broken base, expired auth, CI down, disk full). Halt; remaining issues keep
  `nightshift` and are first up next run.
- **No output cap**: the whole ready queue gets worked. N issues → N PRs.

## Phase 3 — core-gate scan

Read-only. For each PR opened, runs `~/.claude/skills/land/lib/core-gate.sh` and
labels `nightshift-landable` or `nightshift-noland`. The gate is a deterministic
path deny-list — migrations, CI, auth, lockfiles, `.claude/**`, plus repo
`core_paths` from config.

Morning: PRs labelled `nightshift-landable` are the ones where `/land <PR#>` is a
short hop. `nightshift-noland` means read it properly first.

## Config

`.nightshift/config.json` at repo root, all keys optional:

```json
{
  "queue_label": "ready-for-agent",
  "base": "main",
  "max_slots": 3,
  "min_free_mb": 2048,
  "core_paths": ["lib/myapp/billing/**", "src/core/pricing/**"]
}
```

## The report is a deliverable, not a status line

`REPORT.md` is what makes a night you slept through reviewable. It carries the
table, plus two sections that matter more:

- **Needs a human** — every failed issue with its kept worktree, every gate
  refusal, and every *landable* PR flagged with the thing that's easy to forget:
  the gate checks **paths, not correctness**. Nobody read that code.
- **Unverified** — the `git log --grep` that surfaces commits sessions marked as
  unverified.

State what is **not** done and what only a person can judge. A run that ends with
an honest "the rest is yours to judge" is a successful run.

## Artefacts

```
.nightshift/                gitignored
  config.json
  verify.lock/              global mutex (transient)
  <date>/
    run.sh                  emitted driver
    perms.drain.json        deny-list handed to every session
    ledger.tsv              issue \t status \t pr \t diff \t exit \t reason
    <n>.enrich.log
    <n>.log                 full headless one-shot transcript
    <n>.gate.log
    REPORT.md               written at run end; survives /clear
    .finished  .reported  .halt
```

## First run

Use `--dry-run`: pre-flight + enrich + emit `run.sh`, **don't launch**. Read the
driver, check the queue, then run it by hand.

## Anti-patterns

- Holding the loop in-session instead of `nohup`-ing the driver.
- Reading `<n>.log` transcripts into your context. Grep the machine lines only.
- Polling for the run to finish. It's overnight. Come back tomorrow.
- Enriching and draining in one session per issue — you lose the pre-drain view of
  how much of the queue is actually workable.
- Running `/verify` outside the mutex. Port collision reads as "broken at runtime",
  which auto mode treats as a HALT, which feeds the circuit breaker.
- Handing sessions a blanket permission skip instead of the deny-list.
- Asking the user anything after the banner. Nobody's there.
- **Parking on a hunch.** A raw token count is not a threshold. Percentage or ask.
- **Retrying a session that died on a usage limit.** That error is the one piece of
  ground truth you get. Park.
- Dispatching a fourth session because three feels slow. The bottleneck is RAM.
- Letting sessions run the full suite in every subagent.
- Treating a `nightshift-landable` label as "reviewed". It means the diff avoids
  core paths. That is all it means.
- Skipping label creation at pre-flight. Every enrich session then fails
  identically and you learn nothing from the run.
- Handing a session an issue whose brief says `part A only` without passing that
  constraint through. It will build both halves into one unreviewable PR.

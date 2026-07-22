---
name: mergeable-loop
description: Poll-and-drive loop that fires when a PR exists and copilot review is requested — schedules a session cron that each tick reads PR state (read-only), escalates to the drive-to-mergeable autofix cascade once per real change (new copilot findings / red CI), and stops itself on full merge-ready. Composes drive-to-mergeable step 3-6; never merges. Writes two files at the end of every run — an Output artifact (final merge-ready state + what it did) and a rolling Memory log (worked / failed / remember-next) that the next run reads at startup. Use via "/mergeable-loop <PR#>", or auto-invoked from drive-to-mergeable step 3.
disable-model-invocation: true
---

# mergeable-loop

The **watch engine** for `drive-to-mergeable`. Turns "sit here refreshing `gh pr checks`" into a self-pacing 3-minute cron that watches the PR to merge-ready, reacting with the full autofix cascade only when something actually changes, and deletes itself when done. Merge stays the human's — this skill **never** runs `gh pr merge`.

Thin glue. It owns four things and delegates everything else:
1. schedule + tear down the session cron,
2. the per-tick **read-only** poll,
3. the **done-rule** (full merge-ready),
4. the **escalate-once-per-change** guard that keeps a mutating cascade off a bare interval.

Everything mutating (triage → autofix → file issues → resolve threads) is `drive-to-mergeable` steps 4-6, run inline on the ticks that need it.

## When to invoke

- **From `drive-to-mergeable` step 3** — right after the PR exists and Copilot is requested. That's the trigger: PR created + copilot polling begins → hand the wait to this loop instead of blocking.
- **Standalone:** `/mergeable-loop <PR#>` — pick up any open PR and drive it to merge-ready.
- Assumes you're **in the repo checkout** (where d-t-m runs). `pr-checks.sh` reads `origin/<base>` locally.

Do NOT use for: merging (`/merge-pr`), or a pure read-only "ping me when green, don't touch anything" watch (that's a plain `/loop 3m gh pr checks`). This one fixes.

## Setup (once, on invoke)

1. Resolve PR# (arg, or current branch via `gh pr view --json number`). No PR → STOP, suggest `/create-pr`.
2. **Read prior memory** — `runs/MEMORY.md` under this skill's directory (if it exists). Surface the last "remember next run" notes to yourself before starting; act on them (e.g. known-flaky check to ignore, a repo quirk, a bot that posts twice). First run ever → no file, skip.
3. `CronCreate` `*/3 * * * *`, `recurring: true`, prompt = the **Tick** block below with the PR# baked in.
4. Run **Tick** once immediately — don't wait for the first cron fire.
5. Tell the user: loop armed (job ID), 3-min cadence, session-only (dies on exit), auto-expires in 7 days, and that it will self-delete on merge-ready. For an **overnight** wait, say so — session cron won't survive a closed terminal; route to `/schedule` (cloud) instead.

## Tick (what each fire does)

Read-only first. Never mutate before reading.

1. **Poll state** (no writes) — one call does the whole read + verdict:

   ```bash
   bash scripts/bot-reviewed.sh <n> [copilot|coderabbit]
   ```

   Returns `{pr, bot, bot_posted, ready, unresolved_threads, ci:{ok,red,pending,failing,total}, head_sha, verdict}`.
   It composes `pr-checks.sh` (owns `.ready`, unresolved threads) and adds
   bot-posted detection + a genuine CI-red-vs-pending split, then emits the
   `verdict`. Shared with `drive-to-mergeable`.

2. **Branch on `.verdict`:**

   | `.verdict` | Meaning | Action |
   |---|---|---|
   | `DONE` | `ready==true` **and** bot posted | `CronDelete <job>`, run `/pr-ready` for the verdict, run **On finish** (write the two files), notify the user loudly, **STOP**. Never merge. |
   | `ESCALATE` | bot posted **and** (unresolved threads **or** CI red) | run `drive-to-mergeable` steps 4-6 inline: triage every finding (fix-now / file-issue / wontfix), autofix in-scope + regression test, file issues for the rest, resolve threads, re-push. Then report one line and keep looping. |
   | `WAIT` | bot not posted, CI pending, or fix just pushed + re-running | report one terse line (head sha · mergeable · checks pass/fail/pending), keep looping. |

   (`ci.red` counts only fail/cancel buckets — a just-pushed fix with pending
   checks is `WAIT`, never a false ESCALATE.)

3. **Report** one line every tick regardless, so the user sees progress.

## On finish — write two files

Runs at the end of every run — on DONE, **and** on any early stop (user aborts, cron expires, PR closed). Two files under this skill's `runs/` directory (`mkdir -p` it first). Stamp with `RUN=$(date +%Y%m%d-%H%M)` and repo slug `SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner | tr / -)`.

**(1) Output** — `runs/<SLUG>-pr<n>-<RUN>.md` — the artifact the loop produced: the final merge-readiness state + what it actually did. Not a log — the deliverable.
```markdown
# mergeable-loop output — <SLUG> PR #<n>
outcome: MERGE-READY | STOPPED-<reason>   ·   <RUN>

## Final state
<paste the /pr-ready report block>

## What the loop did
- ticks run: <N>   ·   escalations: <M>
- findings fixed in-scope: <list file:line + one-line fix>
- issues filed (out-of-scope): <#numbers + titles>
- threads resolved: <count>
- commits pushed by the loop: <shas + subjects>

## Human next step
<e.g. "review + /merge-pr" — never merged by the loop>
```

**(2) Memory** — append to `runs/MEMORY.md` (rolling, newest entry on top; the next run reads this at Setup step 2). Keep each entry tight — it's read every run, so bloat costs tokens forever.
```markdown
## <RUN> — <SLUG> PR #<n> — <outcome>
- **worked:** <what went smoothly — reuse next time>
- **failed:** <what broke / wasted ticks / dead ends>
- **remember next run:** <actionable — flaky check to ignore, repo quirk, bot double-posts, format-spillover trap hit, baseline-failure to not chase>
```

Only write a **remember-next** line when it's genuinely actionable for a future run. No filler entries — an empty lesson is worse than none (it dilutes the file the next run reads).

## Why this is safe on a 3-min cron

- **No double-mutation.** Cron fires only while the REPL is idle; an ESCALATE cascade keeps the REPL busy, so the next tick can't fire mid-fix. The idle-gate is the concurrency lock — no lock file.
- **No re-triage of handled findings.** After a cascade, threads are resolved and CI is re-running — the next tick reads 0 unresolved + pending CI → WAIT, not re-fix. The PR's own resolved/green state is the memory; no marker file. A *new* copilot review on the new push is genuinely new work and correctly re-escalates.
- **Read before write, every tick.** WAIT and DONE never mutate. Only a real change (unresolved findings / red CI) triggers the cascade.

## Done-rule (explicit)

Stop the loop only when ALL hold (this is `pr-checks.sh` `.ready == true` **plus** copilot):
- copilot review posted
- CI: every check terminal-success (SUCCESS/SKIPPED/NEUTRAL), none pending/failed, `total > 0`
- 0 unresolved review threads
- `mergeable != CONFLICTING`, `mergeStateStatus` CLEAN
- not draft
- commits conventional

Yellow ≠ green. Pending ≠ done. On DONE: `/pr-ready` + notify + `CronDelete`. The merge is the human's call via `/merge-pr`.

## Composes

`drive-to-mergeable` (steps 4-6, the mutating cascade) · `bot-reviewed.sh` (per-tick read + verdict, wraps `pr-checks.sh`) · `pr-ready` (final verdict) · `merge-pr` (the human's next step, not this skill's).

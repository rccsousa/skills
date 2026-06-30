---
name: pr-interview
description: Use before pushing/merging a PR to verify the author understands the diff. Auto-fires from /create-pr Step 4.5, or invoke directly. Picks 3 hunks (1 largest + 2 risk-keyword), asks plain-English explain + edge-case + scope + drift questions. Soft signal, not gate. Triggers - "/pr-interview", "interview me on this PR", "quiz me before push".
---

# pr-interview

Defense against shipping skimmed code. Forces author to articulate diff in own words before push — catches "I copied this from prior PR / agent generated this / I patched on a moving base without re-reading" cases.

## Why this exists

Drift pattern: when an underlying assumption shifts mid-feature, response is patch-on-top, not plan-reset. Hunks ship that the author never re-read in current context. Interview = forced re-read at the temptation moment (push button).

Not a gate. Soft signal — Claude grades, you decide. Override always available.

## Arguments

- `$1` (optional) — PR number. Else current branch via `gh pr view --json number`. If no PR exists yet, work from unpushed commits (`git log origin/<base>..HEAD`).
- `--skip` — bypass interview (ask why once)
- `--style <lite|full|grumpy>` — question depth (default: full)

## Auto-skip conditions

Skip with surfaced reason if:
- `<50 LOC changed` AND `<3 files touched`
- Docs-only (only `*.md` / `*.mdx` / `docs/` paths)
- Revert PR (title starts with `revert:`)

Don't silently bypass.

## Process

### 1. Load context

- Resolve PR (arg or current branch)
- `gh pr diff <num>` if PR exists, else `git diff origin/<base>..HEAD`
- `gh pr view --json title,body,commits,additions,deletions,files` (skip if no PR yet)
- Check auto-skip conditions. If skip: surface reason + exit.

### 2. Pick hunks (hybrid)

Feed the diff to the extractor — it returns per-hunk `{file, hunk, adds,
dels, churn, keywords}` sorted by churn desc (keyword families baked in,
single source of truth):

```bash
gh pr diff <num> | ~/.claude/lib/extract-interview-hunks.sh   # or: git diff origin/<base>..HEAD | ...
```

Then SELECT (this is the judgement, not the script's job):
- **1 largest hunk:** first entry (highest churn).
- **2 risk-keyword hunks:** highest-churn entries with non-empty `keywords`,
  top 2 distinct files, skip if same file as the largest.

<3 hunks meet bar → drop to 1–2 hunks. Surface "small PR — reduced to N hunks."

### 3. Build question set

**Q0 — Scope (always):**

> In 3 bullets: **what / why / risk**. Don't read the PR body.

**Q1–3 — Per-hunk:**

```
Hunk at <file>:<line> (<+adds/-dels>):
<10–15 line diff snippet>

- Plain English: what does this do?
- What if <edge case>?
```

Edge-case picker by hunk semantics:

| Keyword family | Edge case |
|---|---|
| auth/token | "token expired mid-flow / signature replay / clock skew" |
| money/transfer | "amount=0 / negative / float precision loss" |
| webhook | "duplicate delivery / out-of-order / unsigned" |
| migration | "rolled back / partial apply / production rows that violate new constraint" |
| retry | "max retries hit / service permanently down / retry storm" |
| error/log | "failure path — what gets logged / propagate or swallow?" |
| cache | "stale read / race between writers / invalidation missed" |
| (none) | "what if the caller passes `null` / `undefined` / empty?" |

**Q4 — Drift (always):**

> Did the base assumptions hold across all commits, or did something shift mid-feature (schema change, API contract, sibling team's work landing)? If shifted: was this a plan-reset or patch-on-top?

Direct reference to drift-coaching rule. Surfaces the stacking-on-moving-base pattern.

**Q5 — Failure mode (always):**

> Day after merge, prod pages. Most likely cause?

### 4. Ask interactively

Ask Q0. Wait. Q1. Wait. Etc. One at a time.

**Watch during interview:**
- Answer turns terse ("idk", "just push", "whatever") → flag
- Long gap (>5min between answers) → "want to pause + resume tomorrow?"
- Typo density rising → flag
- `date` shows >22:00 local → at end, suggest "late hours, sleep on it"

### 5. Grade

Per answer:
- **Solid** — matches diff intent, edge case named correctly
- **Soft** — partial, vague, or skipped a sub-question
- **Gap** — misses what hunk does / wrong edge-case reasoning / "agent did it" blame without re-reading

Verdict:

| Result | Verdict |
|---|---|
| All Solid | Solid — push when ready |
| ≤1 Soft | Light handwave on Qn: <specific>. Re-read <file:line> if you want |
| ≥2 Soft OR 1 Gap | Re-read before push. Gaps: Qn=<x>, Qm=<y>. Walk through? |
| ≥2 Gap | Pause. You're skimming. Re-read now, or ship tomorrow |

Signal, not gate. You decide.

### 6. Output

```
Interview verdict: <Solid | Soft | Re-read | Pause>

Q0 scope:        <pass/handwave/miss>
Q1 <file:line>:  <pass/handwave/miss>
Q2 <file:line>:  <pass/handwave/miss>
Q3 <file:line>:  <pass/handwave/miss>
Q4 drift:        <pass/handwave/miss>
Q5 failure mode: <pass/handwave/miss>

<verdict + specific re-read suggestions>
```

## Halt / skip

- `--skip` → ask "why skipping?" once.
- Auto-skip → surface reason
- Mid-interview "skip this one" → mark Soft, continue
- Mid-interview "stop" → exit cleanly, no verdict
- After Re-read/Pause verdict + "push anyway" → flag once, no lecture

## Style flags

| Flag | Questions | Time | When |
|---|---|---|---|
| `--style lite` | Q0 + Q4 + Q5 | ~3min | Small PRs that didn't auto-skip |
| `--style full` (default) | Q0–Q5 | ~10min | Most PRs |
| `--style grumpy` | Q0–Q5 + push-back on each Soft | ~15min | When you want harder pressure |

Grumpy ≠ adversarial code review. For that, use `/review-codex-pr`.

## Out of scope

- Verifying CI/threads/conflicts → `/pr-ready`
- Opening the PR → `/create-pr`
- Performing the merge → `/merge-pr`
- Adversarial code review → `/review-codex-pr`

## Design note

Adversarial framing at 22:00 = punishment theater. Goal is re-read, not interrogation. /review-codex-pr exists if you want adversarial — invoke it explicitly.

Interview is a forced re-read at the temptation moment. Auto-fires inside `/create-pr` Step 4.5; standalone for ad-hoc use.

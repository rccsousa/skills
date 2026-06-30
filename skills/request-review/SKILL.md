---
name: request-review
description: Use when transitioning a PR from draft to ready-for-review (or about to ping colleagues). Verifies the review bot has reviewed AND that Critical/Major findings are addressed. Soft signal, not hard gate — surfaces report + HITL approve before flipping draft to ready. Triggers - "/request-review", "ready for team review", "ping the team", "is the bot done?", "mark ready for review".
disable-model-invocation: true
---

# request-review

Gate the draft → ready-for-review transition on the review bot being done.
Defense against fire-and-forget pattern: push PR, ping team immediately, waste
reviewer time on issues the bot already caught.

Works with any automated reviewer. **CodeRabbit** is the reference bot
(default); pass `--bot generic` for plain-English severity labels from other
bots. Below, "the bot" means the configured reviewer.

## Why this exists

Drift pattern: user opens PR draft → bot hasn't reviewed yet → user pings team → colleagues review → bot review lands later → duplicate work + churn. Or: bot reviewed but findings unaddressed → colleagues re-flag same things.

Friction at the temptation moment ("mark ready / ping team") forces the verify step that habit skips.

## Pipeline

```
resolve PR → verify draft state → fetch bot state → classify per severity → HITL approve → gh pr ready → optional ping draft
```

## Arguments

- `$1` (optional) — PR number. Else current branch via `gh pr view --json number`.
- `--bot <coderabbit|generic>` — severity vocabulary (default: `coderabbit`).
- `--bot-login <login>` — bot's GitHub author login (default: `coderabbitai[bot]`).
- `--force` — skip the bot check (use when intentionally bypassing; flag the override once, no lecture).
- `--no-ping` — mark ready, skip ping draft
- `--ping <slack|email>` — draft channel for the ping (default: ask)
- `--no-flip` — surface report only, don't transition draft → ready

## Auto-skip conditions

Skip with surfaced reason if:
- PR already ready-for-review (not draft) → halt "already ready, no transition"
- PR doesn't exist → halt "run /create-pr first"

## Steps

### 1. Resolve PR

- `$1` given → use it.
- Else: `gh pr view --json number,title,isDraft,baseRefName,headRefName,url`.
- No PR for branch → halt "no PR found, run /create-pr first".
- Not draft → halt "already ready-for-review, nothing to do".

### 2. Fetch bot state

```bash
~/.claude/lib/fetch-review-threads.sh <pr>   # → {reviews:[...], threads:[...]}
```

Use `.reviews` for 3a (has the bot reviewed?) and `.threads` for 3b (severity).

**Bot identity:** author.login == the configured `--bot-login` (default `coderabbitai[bot]`, also `coderabbitai`).

### 3. Classify bot state

**3a. Has the bot reviewed?**

- Any review with author == bot → yes
- None → halt: "the bot hasn't reviewed yet. Wait, or pass --force to skip"

CodeRabbit usually lands within 2–5 min of PR open. If user is in a hurry, `--force` is the explicit lever.

**3b. Classify unresolved threads** (only bot-authored threads, per first comment author).

For each thread:
- `isResolved == true` → addressed
- `isResolved == false` AND any reply from PR author → "replied, not closed" (soft open)
- `isResolved == false` AND no PR author reply → open

Classify each first comment body via the shared classifier (single source
of marker truth):

```bash
echo "$body" | ~/.claude/lib/classify-review-severity.sh --bot <coderabbit|generic>
# → {"severity":"critical|major|minor|nit|refactor|verification|unknown", "marker":"...", "bot":"..."}
```

Map the `severity` token to this skill's action:

| `severity`                 | Action     |
|----------------------------|------------|
| `critical` / `major`       | **block**  |
| `minor` / `refactor` / `nit` / `verification` | skip |
| `unknown` (actionable)     | **block**  (fail safe — assume risk) |

### 4. Report

```
PR #123 — feat: xyz  (draft)
base: main ← feature-branch

bot review:   ✓ landed
findings:
  Critical/Major: 2 open, 1 replied-not-closed
  Minor:          4 (skipped per severity filter)
  Nit:            3 (skipped per severity filter)

Open Critical/Major:
  ✗ src/foo.ts:42 — signature replay window not bounded
  ✗ src/bar.ts:88 — amount overflow on negative input
  ⚠ src/baz.ts:15 — (replied but unresolved) timeout handling

BLOCKED — address Critical/Major before requesting team review.
```

On all-clear:

```
PR #123 — feat: xyz  (draft)
base: main ← feature-branch

bot review:   ✓ landed
findings:
  Critical/Major: 0 open
  Minor/Nit:      7 (skipped per severity filter)

CLEAR — ready to flip draft → ready-for-review.
```

### 5. HITL approve

Wait for explicit "go" / "yes" / "flip" / "mark ready". This flips shared GitHub state, so the approval gate is mandatory.

If BLOCKED + user says "force" / "skip bot" / "ready anyway":
- Flag the override once ("Override noted — bot has N open Critical/Major. Proceeding."), no lecture.
- Require second explicit "yes" before flipping.

### 6. Flip to ready-for-review

```bash
gh pr ready <number>
```

Skip if `--no-flip` given.

### 7. Optional ping draft

If `--no-ping` not given, ask:

```
Mark ready done. Ping channel?
  - slack <channel>
  - email <recipient>
  - skip (do it manually)
```

On slack: draft the message, surface it for explicit approval. **Never auto-send.**

Template:

```
PR ready for review: <title>
<url>
+<adds> -<dels>, <N> commits
Issue: <tracker link>
What landed: <one-line from PR body "What" section>
```

Wait for explicit "send" before posting.

## Halt conditions

- No PR for branch → "run /create-pr first"
- PR not draft → "already ready"
- Bot hasn't reviewed → wait OR `--force`
- Critical/Major unresolved → BLOCKED, list threads
- User declines at HITL → exit cleanly

## Out of scope

- Opening the PR → `/create-pr`
- Pre-push code interview → `/pr-interview`
- Mergeability check → `/pr-ready`
- Performing the merge → `/merge-pr`
- Adversarial review → `/review-codex-pr`
- Actually replying to bot threads → manual (user reads + responds)

## Severity filter rationale

Minor/Nit findings are noise tax. Blocking team review on every bot nitpick
would train the user to skip the bot entirely. Critical/Major is the bar —
those are the ones colleagues would flag anyway.

If a "Minor" finding turns out to actually be a bug, that's a feedback-loop signal: user addresses it, optionally updates the filter rule. Not the skill's job to second-guess severity tags case-by-case.

## Why this skill exists

`/create-pr` opens draft. `/pr-ready` verifies merge readiness. `/merge-pr` performs merge.

Gap: the draft → ready-for-review transition. That's the moment user pings humans. The bot may not be done. Findings may be unaddressed. Habit = fire-and-forget. Skill = forced pause + structured verify.

Mirrors `/pr-interview` pattern: soft signal, HITL gate, override always available. Goal is habit reinforcement, not blocking.

## Design notes

- Soft gate, not hard. `--force` always available; flag the override once.
- No auto-ping. Drafts only. User sends.
- Severity classification is best-effort grep; on ambiguity, fail to Major (assume risk).
- If the bot ever changes severity markers, update the marker table in `lib/classify-review-severity.sh` — don't auto-detect from comment structure (too brittle).

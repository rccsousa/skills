---
name: nightshift-prep
description: >
  Get a repo and its backlog ready for an unattended `/nightshift` run. Two jobs:
  first-run repo setup (labels, `.nightshift/config.json` with core_paths inferred
  from the repo, gitignore, permission-ceiling check), then queue curation — score
  every open issue for whether an unattended session could actually finish it,
  recommend a nomination set with reasons, and label the ones you approve. Stops
  at nomination; `/nightshift` does the enriching and the running. Use when the
  user says "/nightshift-prep", "prep the queue", "what can run tonight", or is
  setting up nightshift in a repo for the first time.
disable-model-invocation: true
metadata:
  version: 0.1.0
---

# Nightshift Prep

`/nightshift` runs with nobody watching. **This is the part where somebody is
watching** — the judgement call about what deserves a night of unattended work.

Prep is human-present, interactive, and opinionated. It ends at "these N issues
are nominated". Everything after that (enrich, emit, run) is `/nightshift`.

```
/nightshift-prep [--setup-only] [--curate-only]
  ├─ 1. setup      first run in this repo only — labels, config, gitignore, ceiling
  ├─ 2. score      every open issue against the suitability rubric
  ├─ 3. propose    recommended nomination set, with a reason per issue
  └─ 4. nominate   label the approved ones. Stop.
```

Then: `/nightshift --dry-run` to enrich and emit, or `/nightshift` to go.

## Step 1 — repo setup (skip if already done)

Detect: `.nightshift/config.json` exists **and** the six machinery labels exist →
setup is done, go to step 2. Otherwise do all of it.

### Labels

Sessions cannot create labels — `dontAsk` denies anything outside the repo's
allow-list — so they must exist before any run.

```bash
gh label create nightshift-ready    --color 0E8A16 --description "Nightshift: enriched + grounded, safe to one-shot"
gh label create nightshift-blocked  --color FBCA04 --description "Nightshift: needs a human decision"
gh label create nightshift-done     --color 1D76DB --description "Nightshift: draft PR opened"
gh label create nightshift-failed   --color B60205 --description "Nightshift: session halted"
gh label create nightshift-landable --color C2E0C6 --description "Nightshift: diff avoids core paths (NOT reviewed)"
gh label create nightshift-noland   --color D93F0B --description "Nightshift: touches a core path, needs real review"
```

Already-exists errors are fine.

### Nomination label

Check whether the repo already has one — `gh label list` for anything like
`ready-for-agent`, `agent-ready`, `good first issue`, `automation`. If it does,
use it and set `queue_label`. Do not make a repo maintain two labels that mean
the same thing.

### `.nightshift/config.json`

Infer `core_paths` from what the repo actually has, then show the user and let
them edit. Look for:

- migrations — `priv/repo/migrations/`, `db/migrate/`, `migrations/`
- auth / permissions / policy modules
- money, billing, ledger, payments, pricing — anything whose bugs cost real money
- the app's central domain module, if one is obvious from directory size + fan-in

Universal denies (CI, lockfiles, `.env*`, `.claude/**`) are baked into the gate
and must **not** be repeated here.

```json
{
  "queue_label": "<existing label, or nightshift>",
  "base": "<repo default branch>",
  "max_slots": 2,
  "min_free_mb": 2048,
  "core_paths": ["<inferred>"]
}
```

Start `max_slots` at 2. Raise it after a clean night, not before.

### Gitignore

Add `/.nightshift/` if absent. Say so; don't commit it — that's the user's call.

### Permission ceiling — check it, loudly

`dontAsk` **denies** anything outside `permissions.allow`, silently, with nobody
to ask. The repo's allow-list is the hard ceiling on what a night can do.

Read `.claude/settings.json` and `.claude/settings.local.json`. Confirm the
allow-list covers what `/one-shot` needs end to end: the test runner, the
formatter/linter, `git` (add/commit/push/worktree), and `gh pr create`.

If the test runner isn't allowed, **say so plainly and recommend fixing it
first** — every issue will fail the same way and trip the circuit breaker after
three, which looks like a nightshift bug and isn't.

## Step 2 — score every open issue

```bash
gh issue list --state open --limit 100 --json number,title,body,labels,comments
```

Score each against the rubric. This is a **read-only pass** — no labels yet, no
enrichment. Read bodies and comments; a comment often kills an issue the title
made look easy.

### The rubric

An issue is **GOOD** for unattended work when all hold:

- **Bounded.** One coherent change. If it reads like two features joined by
  "and also", it needs splitting first.
- **Acceptance a machine can check.** Tests, a build gate, an observable
  behaviour change. `/nightshift` runs unattended and cannot look at a screen.
- **No human decision left in it.** Product calls, naming debates, "ask @X" — all
  disqualify.
- **Groundable in code.** The fix is discoverable by reading the repo, not by
  watching production.

**REJECT** when any of these are true — and name which one:

| Signal | Why it fails |
|---|---|
| Acceptance needs a runtime measurement, a benchmark, a profile, or a screenshot comparison | An unattended session cannot produce that evidence, so it either stalls or ships a PR claiming verification it never did |
| The issue itself says "investigate", "measure first", "do not X blind" | It's an investigation. The honest output is findings, not a PR |
| Needs a product or design decision | Nobody is awake to make it |
| Depends on an unmerged PR or another open issue | The base will be wrong |
| Body is one line with no reproducible detail and no comments | Enrichment may rescue it — mark **MAYBE**, not GOOD |
| Touches only `core_paths` | It can be built, but never auto-landed. Fine to nominate; say so |

**MAYBE** — thin but groundable. Nominating these is how you find out whether
enrichment is doing its job. Flag them as the experiment they are.

### Check for work already in flight

For each candidate, before scoring it GOOD:

```bash
gh pr list --search "<issue number>" --state all --json number,headRefName,state
git branch -a --list "*<issue-number>*"
```

An existing branch or an open PR means somebody already started. Downgrade to
REJECT with `work already in flight` — a second attempt produces a competing PR.

### Check it's actually open

Issues close between sessions. Re-read state at nomination time, not from a
cached list.

## Step 3 — propose

Print one block. Terse, one line of reasoning each, worst news first.

```
CURATION — <N> open issues

GOOD
  #426  concrete scope, names its own test, no core paths
  #636  vague but groundable; expect an A/B split

MAYBE
  #580  follow-ups list, unclear if all still apply

REJECT
  #645  acceptance requires a measured before/after — unattended can't produce it
  #418  investigation, not a fix
  #549  needs a runtime diff against an external tool

recommend nominating: #426 #636
```

Then ask once, with `AskUserQuestion`, offering the recommended set as the first
option. Let the user edit the set. **Never nominate without a yes** — nomination
is the consent boundary the whole design rests on.

## Step 4 — nominate

For each approved issue:

```bash
gh issue edit <n> --add-label "<queue_label>"
```

Verify each landed (`gh issue view <n> --json labels`) — GitHub's index lags, so
a list query straight after can come back empty while the edit succeeded. Check
the issue, not the list.

Then report, and stop:

```
nominated 2 — #426 #636

next:  /nightshift --dry-run    enrich + emit the driver, don't launch
       /nightshift              enrich, emit, and run it
```

Do not enrich. Do not emit. Do not run. Prep ends here.

## Anti-patterns

- **Nominating to fill a queue.** Two good issues beat six that fail at 03:00. A
  thin night is a successful night.
- **Scoring from titles.** Read the body and the comments. Today's rejection came
  from an acceptance criterion four lines into the body.
- **Nominating an issue with an open PR or an existing branch.** You get a
  competing PR and a merge conflict nobody is awake to resolve.
- **Skipping the permission-ceiling check.** A missing test-runner permission
  fails every issue identically and reads as a nightshift bug.
- **Inferring `core_paths` and not showing them.** The gate is the only thing
  standing between an unattended PR and a core path; the user must see the list.
- **Setting `max_slots` above 2 before a clean night.**
- **Enriching here.** That's `/nightshift`'s step 3. Two copies of that logic will
  drift.

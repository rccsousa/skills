---
name: one-shot
license: MIT
description: >
  End-to-end feature orchestration: plan → implement → review → fix. Three autonomy
  modes (hitl, grill, auto) control where human checkpoints land. Defaults to grill
  (HITL + `/grill-with-docs` checkpoints between phases, ADRs written
  post-implement); `auto` is opt-in behind a
  risk-ack flag and the invoker owns the call. Planning docs (PRD/issues/plan)
  are scratch — deleted post-implement; ADRs are the durable record.
  Use when shipping a feature from
  idea to merge-ready with minimal context-switching, or when the user says "ship
  this", "run the pipeline", "take this through", or "one-shot this".
---

# One-Shot

Orchestrate a feature end-to-end. Each phase dispatches the right specialised agent,
verifies the artefact, and feeds the next phase. Merge is always performed manually
by the user on GitHub — the skill stops at "ready to merge".

## When to use

- User asks to "ship this", "take this through", "run the pipeline", "one-shot this"
- A plan, PRD, or issues file already exists and execution is the next step
- Multi-phase work where re-briefing each phase would waste context

Skip for trivial edits (typo, rename, single-line fix) — fix inline.

## Three modes

```
/one-shot [target] --mode=hitl|grill|auto [--i-understand-the-risk]
              [--max-parallel=N] [--no-parallel]
```

Parallelization defaults to **unbounded** ("crazy mode") — one-shot fans
out every phase that can run in parallel with no cap unless `--max-parallel=N`
throttles it. `--no-parallel` forces full serial fallback. See the
**Parallelization** section below.

`target` is optional. Auto-detected when present:

- `plans/*.md` → plan-driven flow
- `prds/*-issues.md` → issue-driven flow
- `prds/*.md` (no issues file) → PRD-driven flow
- Else: treat as a free-text brief, ask once how to enter the pipeline

| Mode  | Trigger                                                       | Net effect                                          |
|-------|---------------------------------------------------------------|-----------------------------------------------------|
| hitl  | `--mode=hitl`                                                 | User signs off between phases. Safety net on.       |
| grill | **default** — no flag, `--mode=grill`                         | HITL + `/grill-with-docs` checkpoints + post-impl ADR write. |
| auto  | `--mode=auto --i-understand-the-risk` (both required)         | Unattended cascade. Companion-skill gates lifted.   |

`hitl` + `grill` are safe defaults — both keep the human on the critical path
for every externally visible action (commit, push, PR open, GH thread reply).
Grill is the default because most non-trivial features benefit from at least
one round of "are you sure" before committing to direction.

## ⚠️ Auto mode — opt-in, gated, loud

Auto mode lifts the per-action confirmation gates in the companion skills
(`create-commit`, `create-pr`, `code-fix`) and lets the cascade run end-to-end
without user prompts between phases.

**The invoker owns the call.** Anything Claude commits, pushes, or posts is
attributed to the user's git + `gh` identity and is visible to teammates,
clients, and CI. Auto mode is project-agnostic — one-shot does not know
whether a repo is solo or shared. Pick the mode that matches what you can
own. Bugs land without review. Bad PR bodies ship. Wrong branches get pushed.
Use with full awareness.

### Activation requirements (all must hold)

1. **Both flags present:** `--mode=auto` AND `--i-understand-the-risk`.
   The risk-ack flag has no shorthand. Typing it confirms intent.
2. **No disable marker:** if `.claude/auto-mode-disabled` exists at repo root,
   or `~/.claude/auto-mode-disabled` exists globally, refuse + halt. Either
   marker is a hard veto — drop the file to opt a repo (or your entire
   environment) out of auto mode.
3. **Branch != base:** never run auto mode on `main` / `master` / repo default.
4. **`gh` authed as a single known user** (no ambiguous identity).

If any requirement fails → halt with the specific reason. Never silently
downgrade to `hitl` — the user asked for `auto` explicitly, surface why it
can't run.

### Upfront banner (always)

Before any unattended action, surface a single block listing exact actions
that will execute. User has one chance to cancel.

```
⚠️  AUTO MODE ENABLED — UNATTENDED CASCADE

repo:        <owner/name>
branch:      <head> → <base>
plan:        <path or "free-text brief">
mode chain:  /create-commit --auto  +  /code-review (local)  +
             /code-fix --mode=auto (local)  +  /create-pr --auto

actions that will execute without further prompts:
  - stage + commit (Conventional Commits, no co-author)
  - local code-review on branch diff vs base (no GitHub write)
  - apply fixes + commit (still local, no push)
  - git push -u origin <branch>
  - gh pr create --draft

actions NEVER taken in auto mode (hard caps):
  - gh pr merge
  - git push --force / --force-with-lease
  - git commit --no-verify / --amend
  - any write to main / master / repo default branch
  - any edit outside this repo
  - touching .env / credentials / lockfiles outside scope

audit log: .claude/auto-mode.log (append, never deleted)

  [enter] proceed     [c] cancel
```

After the banner, no further prompts unless a halt condition fires.

### Per-action audit log

Every unattended action appends one line to `.claude/auto-mode.log`:

```
2026-05-21T14:32:18Z  one-shot  commit  abc1234  feat(auth): bound replay window
2026-05-21T14:33:12Z  one-shot  review  local   1 must-fix, 1 consider, 1 nit
2026-05-21T14:33:48Z  one-shot  fix     def5678 fix(auth): rethrow refresh err
2026-05-21T14:34:02Z  one-shot  push    rs/auth/rotate → origin
2026-05-21T14:34:15Z  one-shot  pr_open #1234 https://github.com/.../pull/1234
```

User can audit + revert with `git log` + `gh pr view` after the fact.

### Hard caps in auto mode

These are never lifted, even with the risk-ack flag:

- No `gh pr merge` — merge is always user.
- No force-push of any kind.
- No `--no-verify` (hooks always run).
- No `--amend` (always a new commit).
- No write to default branch — refuse if branch == base.
- No `gh issue create` (suggested follow-ups still surface in return payload).
- No `gh pr merge --auto` (queued merge).
- No edits to `.env`, credentials, or files outside the worktree.
- Halt immediately on any failing check — never retry, never silently skip.

### Per-phase behaviour

| Phase            | hitl                          | grill (default)                                        | auto (gated)                                  |
|------------------|-------------------------------|--------------------------------------------------------|-----------------------------------------------|
| brief → PRD      | user writes / interactive     | `/grill-with-docs` (no ADR writes yet — deferred)      | requires plan file — no PRD generation        |
| PRD → issues     | user reviews + reorders       | `/grill-with-docs` on slice cuts (local only — no `gh issue create`) | requires issues file pre-split  |
| plan             | manual or `writing-plans`     | council mandatory + `/grill-with-docs`                 | plan must exist before invocation             |
| council          | opt-in (user requests)        | always-on                                              | always-on (multi-lens planning is parallel)   |
| implement        | TDD commits, hard-stop after  | TDD commits + manual smoke list                        | TDD commits, no stop                          |
| review (local)   | local draft review on branch  | local draft, user reads                                | local draft, pipes straight to fix            |
| cascade gate     | pause for user ack            | `/grill-with-docs` on findings packet                  | no gate — pipe straight to fix                |
| fix (local)      | must-fix+should-fix+sensical consider, user acks | per-finding approval                 | must-fix+should-fix+sensical consider committed |
| **ADR write**    | skipped (user owns ADRs)      | `/grill-with-docs` writes ADRs from final code         | `/grill-with-docs --auto` writes ADRs         |
| push + PR open   | user runs `/create-pr`        | user runs `/create-pr`                                 | `/create-pr --auto` pushes + opens draft PR   |
| merge            | always user                   | always user                                            | always user (hard cap — never auto-merged)    |

## Parallelization — crazy mode

Default = fan out everything that can fan out, with no cap. Phases that have
real dependencies stay serial; phases that don't, run flat.

**What runs in parallel (default ON across all modes):**

| Phase                | Parallel?         | Strategy                                                                                  |
|----------------------|-------------------|-------------------------------------------------------------------------------------------|
| brief → PRD          | no                | single planner agent                                                                      |
| PRD → issues         | no                | single slicer agent                                                                       |
| council              | **yes**           | already parallel — one agent per lens (arch / sec / perf / UX / domain / ops)             |
| implement (1 PR)     | no                | TDD red→green dependency forces serial steps                                              |
| implement (N issues) | **yes**           | one one-shot per issue in its own worktree, up to `--max-parallel` (default ∞)        |
| review               | **yes**           | one agent per lens (security / correctness / plan-vs-diff / perf / nit / CI-build)        |
| fix                  | **yes**           | one worker per file-partition of findings, each in own worktree, then cherry-pick back    |
| merge                | no                | always user                                                                               |

Parallelism is invisible to the user — they see merged findings packets and
aggregated commit lists, not the underlying fan-out. The orchestrator picks
fan-out width per phase from the input shape (lens count, finding partitions,
issue count), capped only by `--max-parallel` if set.

**Throttles:**

- `--max-parallel=N` — cap any single fan-out at N agents (default unbounded)
- `--no-parallel` — full serial fallback (useful for debugging or rate-limited
  environments)

**Hard rules that survive parallelization:**

- TDD steps inside a single PR stay serial — red→green→commit is a dependency
  chain, not a fan-out opportunity.
- Final aggregation (cherry-pick onto head branch) is **always sequential** so
  history stays linear and conflicts surface cleanly.
- Test suite runs once on the aggregated branch before fan-out closes —
  per-worker local tests are best-effort; the head-branch run is authoritative.
- Halt the entire phase if any worker reports conflict, test failure, or
  unrecoverable error. Never silently drop a worker's output.

**Per-phase fan-out details:**

- **Review** — see `/code-review` parallelization section. Lens agents run flat,
  emit partial findings packets, orchestrator merges + dedups by file:line
  picking max severity.
- **Fix** — see `/code-fix` parallelization section. Findings partition by file
  (disjoint by construction), one worker per partition in its own worktree,
  orchestrator cherry-picks all commits back onto head branch in deterministic
  order (file path → sha).
- **Multi-issue implement** — when entering from PRD → issues, default fan-out
  is one issue per worker. Each runs the full per-issue inner loop (plan →
  implement → review → fix). Aggregation = N separate PRs, one per issue. Not
  a single merged branch.

## Phase pipeline

```
brief
  │
  ├─ (multi-PR scope?) ──► PRD (local) ──► issues (local) ──► loop per issue
  │
  └─ plan ──(council if warranted)── implement ── review (local) ── fix (local) ── ADR write ── retire scratch ── push + create-PR ── ready-to-merge
```

**Review + fix run on the local branch** before push + PR open. The
findings packet flows in-memory from `/code-review` to `/code-fix` with no
GitHub roundtrip.

**PRD + issues stay local** in grill mode — no `gh issue create` calls
during planning. Issues become GitHub issues only when the user runs
`/prd-to-issues --post` explicitly. This keeps planning iteration cheap.

**ADRs are written post-implement, not during planning.** In grill mode,
`/grill-with-docs` stress-tests the brief / PRD / plan against existing
CONTEXT.md + ADRs but **defers writing new ADRs** until after implement
+ review + fix complete. The post-implement ADR-write phase captures
decisions that actually crystallised in code, not aspirational decisions
that may have shifted mid-implementation.

Push + PR open happens last, so the PR opens already-reviewed,
already-clean, and with ADRs reflecting what shipped. No force-push, no
thread re-resolution, no public churn from review iteration.

### Artefact lifecycle — scratch vs durable

Planning artefacts are **scratch**; ADRs are the **durable record**. A merged
feature leaves behind code + tests + ADRs, not stale planning docs. The
pipeline retires its own scratch as it goes.

| Artefact             | Lane      | Who deletes                        | When                                   |
|----------------------|-----------|------------------------------------|----------------------------------------|
| `prds/<f>.md`        | multi-PR  | `issue-worker` (last issue)        | during implement, staged in commit     |
| `prds/<f>-issues.md` | multi-PR  | `issue-worker` (each + last issue) | per issue + final, staged in commit    |
| `plans/<f>.md`       | single-PR | one-shot                           | after ADR write (step 7), own commit   |
| `docs/adr/*.md`      | both      | **never deleted**                  | written post-impl (step 7), durable    |

Deletion is **committed, not bare `rm`** — the removal is staged into a commit
so history records that the scratch existed and was retired (recoverable later).
`issue-worker` already does this for PRD/issues (`git add` of the removals in
the final issue commit); one-shot mirrors it for `plans/` in the single-PR lane.
The deletion commit obeys the same `/create-commit` gate as every other commit
(on in `hitl` + `grill`, lifted in `auto`).

**Ordering vs ADR write is intentional.** `issue-worker` deletes the PRD
*during* implement (step 3), before step-7 ADR write — and that's fine in
`grill` + `auto`: ADR-write reads the **diff** (what shipped) + existing ADRs,
never the PRD. The single-PR `plans/<f>.md` is an *input* to ADR-write, so it
outlives step 7 and is deleted immediately after.

**hitl guard.** In `hitl`, the pipeline does **not** write ADRs (step 7 is
skipped — the user authors ADRs by hand). But `issue-worker` still deletes
PRD/issues during implement, which would strip the planning context the user
needs to write those ADRs. So in `hitl` mode one-shot **restores PRD/issues
from the deletion commit** (`git checkout <commit>^ -- prds/<f>.md
prds/<f>-issues.md`) right after implement and **holds final retirement** until
the user confirms their ADRs are written. Same for `plans/<f>.md` in the
single-PR lane — kept until the user signs off. The scratch is only retired
(committed deletion) once the user says ADRs are done, or explicitly opts to
skip ADRs. Never silently strip a hitl user's planning docs out from under them.

### 0. Resolve repo config

Before the scope check, read `docs/agents/one-shot.md` (if your repo provides one) for repo-specific locations. Fall back to
defaults when the file or a field is absent:

| Config            | Source field in `docs/agents/one-shot.md` | Default                  |
|-------------------|--------------------------------------------|--------------------------|
| ADR-write target  | **Location** under "ADR writes"            | `docs/adr/`              |
| Plans location    | **Location** under "Plans"                 | `plans/`                 |
| PRD/issues loc    | `docs/agents/prds.md` (**Location**)       | `prds/`                  |
| Base branch       | **Base** under "Base branch"               | repo default branch      |
| Auto-mode veto    | `.claude/auto-mode-disabled` presence      | allowed (no marker)      |

Substitute these wherever this skill names `docs/adr/`, `plans/`, `prds/`, or a
base branch below. The auto-mode veto is read from the marker file directly (see
the auto-mode section), not from `one-shot.md` prose. Proceed silently if
`docs/agents/one-shot.md` is missing — the defaults are correct for most repos.

### 1. Scope check

Determine pipeline shape once, up front:

- **Trivial edit** → skip the skill entirely.
- **Single-PR feature** → plan → implement → review → fix.
- **Multi-PR feature** → PRD → issues → per-issue plan → implement → review → fix.
- **Cross-system epic** → PRD covering multiple slices, per-slice loop.

Ask once if ambiguous. Don't re-ask mid-flow.

### 2. Plan / PRD phase

Use the matching shipped skill:

- Single PR: `writing-plans` (superpowers) or whatever planning skill the project uses.
- Multi-PR: `/write-a-prd` (from the `building` plugin in this marketplace).
- Multi-slice: `/write-a-prd` + `/prd-to-issues`.

In `grill` mode, run **`/grill-with-docs`** on the brief before the PRD lands
and on the issue cuts before splitting. `grill-with-docs` reads existing
`CONTEXT.md` + `docs/adr/*.md` and stress-tests the plan against them.

**Defer ADR writes.** The default `/grill-with-docs` behaviour is to update
CONTEXT.md + write new ADRs inline as decisions crystallise. Inside
one-shot grill mode, this is **suppressed** for ADR writes — the ADR-write
step happens AFTER implement + review + fix (see step 7). CONTEXT.md fixups
that just sharpen terminology can still land inline.

**PRD + issues stay local.** No `gh issue create` calls during planning.
`/prd-to-issues` writes the slice file locally; pushing to GitHub is a
separate explicit step the user runs when (and if) they want issues filed.

In any mode, run `/council-of-agents` when:

- Two or more concerns intersect (backend × UX, security × perf, domain × ops)
- Scope is multi-stakeholder
- Architecture calls are open
- `grill` mode (always)

### 3. Implement phase

Dispatch a worker agent with `isolation: "worktree"`:

- Default model: latest Sonnet. Escalate to Opus only on `needs-opus`-tagged plan steps.
- Discipline: TDD per step (red → green → commit).
- For issue-driven flows, the worker invokes `/issue-worker` one issue at a time.
  Each run removes its issue from the issues file; the **last** issue also
  deletes the PRD + issues file, staged into that commit. PRD/issues are
  scratch — ADRs (step 7) are the durable record. See **Artefact lifecycle**.
- Commits via `/create-commit` (Conventional Commits, no Claude co-author).
  Confirmation gate is ON in `hitl` + `grill`; lifted in `auto` (with risk-ack).

After implement: branch has N local commits, **nothing pushed yet, no PR yet**.
Cascade continues into local-mode review.

### 4. Review phase — local diff

Dispatch a review agent that invokes `/code-review` (companion skill in this plugin).

`/code-review` reads the **local diff** (`git diff <base>...HEAD`), compares against
the plan, classifies findings into must-fix (bug / security / regression) /
should-fix (clear defect, non-blocking) / consider (correctness / clarity,
judgement-call) / nit (style / polish), and emits a structured YAML
findings packet with `source: local`.

All modes (`hitl` / `grill` / `auto`): local draft only. Packet handed
in-memory to fix agent. **Nothing posted to GitHub** — PR doesn't exist yet.
PR doesn't need to exist for review to happen.

### 5. Cascade gate

Between request and receive, the gate behaves per mode:

- `hitl`: pause for explicit user OK ("proceed", "fix it"). User can edit findings.
- `grill`: run `/grill-with-docs` on the findings packet first — confirms
  severity calls against the existing domain model + ADRs before the fix
  agent fires. ADR writes still deferred to step 7.
- `auto`: no gate. Findings pipe straight into `/code-fix --mode=auto`.

### 6. Fix phase — local commits

Dispatch a fix agent that invokes `/code-fix --findings=<packet>` (companion skill in this plugin).

`/code-fix` reads `source: local` from the packet, always fixes must-fix +
should-fix + sensical consider, applies fixes, commits via `/create-commit`.
**No push, no thread replies** — PR doesn't exist yet. All modes stop at "fixes
committed locally".

**Scope:** must-fix + should-fix always; consider only when sensical
(judgement-call ones deferred). Nits skipped unless cheap. Out-of-scope findings →
surface to user as suggested follow-up issues; never file issues unattended
even in `auto` (hard cap).

**Mode mapping** (one-shot → code-fix):

- `hitl` → `/code-fix --mode=ack` (surface diff, await user OK)
- `grill` → `/code-fix --mode=approve` (per-finding "fix / defer / followup")
- `auto` → `/code-fix --mode=auto --i-understand-the-risk` (apply + commit
  locally, no push)

### 7. ADR write — post-implement documentation

Code is reviewed + fixed + stable. Now extract the decisions that actually
crystallised and write them up as ADRs.

Dispatch a doc agent that invokes `/grill-with-docs` in **ADR-write mode**:

- Input: the merged diff + plan file + existing `docs/adr/*.md`
- Walk the diff for decisions that meet ADR-worthy bar (architectural,
  cross-cutting, hard-to-reverse, surprising-without-context)
- Write new ADR file(s) under `docs/adr/NNNN-<slug>.md`, numbered after the
  highest existing ADR
- Commit via `/create-commit` as `docs(adr): <slug>` — one commit per ADR

**Mode behaviour:**

- `hitl`: skip — user owns ADRs and writes them by hand. **hitl guard
  applies:** restore PRD/issues (and keep `plans/<f>.md`) so the user has the
  planning context, and hold scratch retirement until they confirm ADRs are
  written. See **Artefact lifecycle → hitl guard**.
- `grill`: `/grill-with-docs` proposes ADR text; user approves each before
  the commit lands. CONTEXT.md fixups land alongside if terminology shifted.
- `auto`: `/grill-with-docs --auto --i-understand-the-risk` writes + commits
  ADRs without prompts. Still subject to the auto-mode disable veto.

**Why post-implement, not pre:** ADRs written at planning time bake in
assumptions that often shift during TDD. Post-impl ADRs document what
actually shipped, not what was planned. The decisions that didn't survive
contact with the code never become ADRs.

**Skip conditions:**

- No new ADR-worthy decisions in the diff → skip (most small features)
- `--no-adr` flag (not yet implemented) — manual override
- ADR-write halt → fall through to step 8 anyway; ADRs can be added later

### 7b. Retire scratch planning docs

Once ADRs are committed, the planning docs that drove this work are scratch.
Retire them (see **Artefact lifecycle** for the full table):

- **Multi-PR lane:** PRD + issues are already gone — `issue-worker` deleted
  them during implement. Nothing to do here.
- **Single-PR lane:** delete `plans/<feature>.md` and stage the removal into
  its own commit (`chore: retire <feature> plan`), or fold it into the ADR
  commit. Skip if no plan file was used (free-text brief).

The deletion commit obeys the standard `/create-commit` gate (on in `hitl` +
`grill`, lifted in `auto`). ADRs and `docs/adr/*.md` are **never** touched here.

**hitl:** do not retire scratch yet — hold all planning docs (PRD/issues +
`plans/<f>.md`) until the user confirms their hand-written ADRs are done or
opts to skip ADRs. Then retire. See **Artefact lifecycle → hitl guard**.

### 8. Push + create PR

After ADR-write, branch is reviewed + fixed + documented. Now open the PR.

- `hitl` / `grill`: hard stop — user runs `/create-pr` manually when ready.
- `auto`: cascade continues into `/create-pr --auto --i-understand-the-risk`
  (push + draft PR open).

The PR opens **already-reviewed, already-clean, with ADRs reflecting what
shipped**. Optional standalone PR-mode review can still run after open if
the user wants to post findings to the PR itself, but the inner-loop
review already happened locally.

### 9. Ready-to-merge summary

After PR open, surface a single concise block. Never run `gh pr merge`.

```
PR #<number> — <title>
URL:        <url>
CI:         <green | red | pending>  (gh pr checks)
Plan file:  <path>
Commits:    <N> (from one-shot)

Merge when ready.
```

## Cascade design — explicit

The "request → receive" cascade is the heart of the review loop. Modelled as two
sequential agents with structured handoff:

```
[review agent]            [orchestrator gate]              [fix agent]
  ↓                              ↓                              ↓
  reads PR + plan         waits per mode:                reads findings packet
  produces findings       - hitl:  user ack              applies must+should+consider
  packet (YAML-ish)       - grill: /grill-with-docs      commits via /create-commit
  hitl/grill: in-mem      - auto:  no gate               hitl/grill: stop, user pushes
  auto: also posts        ────────────────────►          auto: push + reply threads
  via gh pr review
```

Packet handoff is in-memory between agents in `hitl` + `grill`. In `auto`, the
review agent additionally posts findings to GitHub and the fix agent pushes +
replies on resolved threads.

**Findings packet shape:**

```yaml
pr: 1234
url: https://github.com/.../pull/1234
ci_status: green
must_fix:
  - file: src/auth.ts
    line: 42
    summary: signature replay window unbounded
    suggestion: enforce 5-minute window per ADR-014
should_fix:
  - file: src/handler.ts
    line: 88
    summary: error swallowed in catch block
nit:
  - file: src/util.ts
    line: 12
    summary: prefer const over let
merge_blocking:
  red_findings: 1
  failing_checks: 0
```

The fix agent consumes this verbatim — no re-discovery needed.

## Council of agents — when to call

Invoke `/council-of-agents` in front of the plan phase when:

- Scope spans multiple lenses (architecture × UX, security × perf, domain × ops)
- A single planning round would miss a concern
- Mode is `grill` (always)

Skip for narrow single-PR work. See the council-of-agents skill for member dispatch
+ synthesis details.

## Dispatch rules

- **Default model:** latest Sonnet for all worker agents unless plan step tagged `needs-opus`.
- **Isolation:** `isolation: "worktree"` for the implement phase only.
- **Sequential, not parallel:** each phase consumes prior phase output (PR #, review URL).
- **Foreground:** keep agents in foreground when their output feeds the next dispatch.

## Halt conditions

Stop + return to user when:

- Implementation agent reports a blocker (failing test it can't fix, ambiguous spec,
  missing fixture)
- Review surfaces a must-fix requiring architectural rethink (not a local fix)
- CI is red after fix + cause isn't obvious
- Merge target diverged — surface, do not auto-rebase
- PR size balloons past ~1k LOC → stop, recommend split

In all halt cases: summarise state, ask user, do not silently retry.

## Worker prompt skeletons

Each prompt briefs the agent cold. Always include:

1. Phase name + artefact path (plan / PR / review URL).
2. Project conventions (PR size cap, commit format, no co-author).
3. Expected return payload shape.
4. Model hint ("Sonnet unless step tagged `needs-opus`").

### Implement-phase prompt

```
You are the implementation worker for <feature-name>. Plan: <absolute-path>.

Read the plan in full, then execute task-by-task with TDD (red → green → commit
per step). Default to Sonnet; escalate only on steps tagged `needs-opus`.

Mode: <hitl|grill|auto>

Constraints:
- Keep diff under ~1k LOC. If scope balloons, stop + report.
- Commit via `/create-commit`. Pass `--auto --i-understand-the-risk` ONLY if
  one-shot mode is `auto` AND the upfront banner was accepted; otherwise
  the confirmation gate stays ON.
- All modes: HARD STOP after commits. Do NOT push. Do NOT open PR. Branch
  stays local for the review + fix phases. Push + PR open happens at the
  tail of the cascade, AFTER review + fix.
- Verify tests + format + lint green locally before reporting done.
- Defer manual smoke-testing steps to the user; list in your return payload.

Return: branch name, commit SHAs, local test/lint status, deferred-tasks summary.
```

### Review-phase prompt

```
Run `/code-review` on the current branch (local mode — no PR yet) with these flags:
- `--plan=<plan-path>` (compare against plan, flag missing tasks)
- `--base=<base-branch>` if branch's base isn't the repo default
- NO `--post` flag in any mode — review runs locally before push.

Return: the YAML findings packet emitted by /code-review verbatim (source: local).
```

### Fix-phase prompt

```
Run `/code-fix` (no PR arg — packet has `source: local`) with:
- `--findings-inline` (packet pasted below)
- Mode = <hitl|grill|auto> → `--mode=ack|approve|auto`
- auto mode additionally requires `--i-understand-the-risk`

All modes apply + commit locally only. Do NOT push (push happens in next
phase via /create-pr). Never run `gh pr merge` — merge is always user.

Findings packet:

<paste findings packet from /code-review here>

Return: the return payload from /code-fix verbatim (commit SHAs, tests status,
suggested follow-ups, ready_for_pr boolean).
```

### ADR-write phase prompt (grill + auto modes)

```
Run `/grill-with-docs` in ADR-write mode on the current branch.

Inputs:
- merged diff vs base
- plan file (if any): <plan-path>
- existing ADRs: docs/adr/*.md

Walk the diff for decisions that meet the ADR-worthy bar (architectural,
cross-cutting, hard-to-reverse, surprising-without-context). For each:
- Write a new ADR under docs/adr/NNNN-<slug>.md (number after highest existing)
- Commit via /create-commit as `docs(adr): <slug>` (one commit per ADR)

Mode:
- grill: propose each ADR for user approval before commit
- auto:  /grill-with-docs --auto --i-understand-the-risk (commits unattended)

Skip entirely if the diff has no ADR-worthy decisions.

Return: list of ADR files written + commit SHAs, or "no ADRs needed".
```

### Push + PR-open phase prompt (auto mode only)

```
Run `/create-pr --auto --i-understand-the-risk` on the current branch.
hitl/grill modes skip this — user runs /create-pr manually.

Return: PR number, URL, draft status.
```

## Dependencies

This skill chains other skills in the same marketplace. The cascade is
self-contained inside this plugin:

**This plugin (`one-shot`):**

- `council-of-agents` — front-phase amplifier
- `code-review` — review side of cascade (produces findings packet)
- `code-fix` — receive side of cascade (consumes findings packet)
- `create-pr` — push branch + open PR
- `create-commit` — staged commit w/ Conventional Commits, no Claude co-author

**`building` plugin (this marketplace, optional but recommended):**

- `/grill-with-docs` — used at every `--mode=grill` checkpoint (brief, PRD,
  issues, plan, findings packet) AND at the post-impl ADR-write phase
- `/grill-me` — bare-bones grilling, available standalone but unused in the
  grill-mode cascade (grill-with-docs is strictly more useful when CONTEXT.md
  + ADRs exist)
- `/write-a-prd` — multi-PR feature → PRD lane
- `/prd-to-issues` — PRD → issues split
- `/issue-worker` — per-issue implementation

**External (soft dep — only if used):**

- `superpowers` — for `writing-plans` + `subagent-driven-development`. Any
  equivalent planning + TDD-discipline skill works; the orchestrator just needs
  a plan file path as input. Not required for the review cascade.

The review cascade (`code-review` → `code-fix`) lives entirely in this plugin. No
external install needed for the core loop.

## Output style — caveman ultra (under-the-hood)

This skill + every sub-skill it dispatches operate in caveman ultra mode for
their generated outputs. Token saver, not presentation choice.

**Applies to:** findings packets, PR bodies, commit messages, review comments,
inter-phase handoff notes, summaries surfaced to user, return payloads.

**Does NOT apply to:** code blocks (verbatim), file paths, line numbers,
identifiers, error strings, halt messages, quoted plan tasks.

**Rules:**

- Drop articles (a / an / the), filler (just / really / basically)
- Fragments OK
- Short synonyms: DB / auth / fn / req / res / impl
- Arrows for causality: `X → Y`
- One word when one word suffices
- Code blocks + quoted errors unchanged

Each companion skill in this plugin (`code-review`, `code-fix`, `create-pr`,
`create-commit`) embeds the same rule in its own SKILL.md → consistent voice
across the cascade.

## Why this skill exists

Without orchestration, each phase needs a fresh prompt + full re-briefing. The
orchestrator hands artefacts forward (plan path → PR number → review URL →
findings packet) so the user only intervenes on halts.

Mode picks where the friction lands:

- **hitl** — production-critical or unfamiliar code; reviewer-then-decide
  between phases, no extra friction.
- **grill** — **default.** HITL + `/grill-with-docs` checkpoints surface assumptions
  before they harden. Catches drift earlier than hitl alone.
- **auto** — invoker has decided the per-phase user prompt earns no safety for
  this run. Gated behind `--i-understand-the-risk`, hard-capped against merge /
  force-push / no-verify / writes to main / issue creation / thread resolution.

Defaults to `grill` because the second-cheapest moment to catch a wrong
assumption is a grill prompt, and the cheapest moment doesn't exist (it's
already gone). Drop to `hitl` for low-stakes flows where the extra grill
prompts cost more than they save. Auto exists for the cases where the
invoker has weighed it and decided otherwise.

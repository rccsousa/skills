---
name: triage
license: MIT
description: >
  Turn raw tester/user feedback into curated, agent-pickup GitHub issues, one
  item at a time. Feedback arrives two ways: pasted (a message + screenshots) OR
  pulled from a Basecamp inbox column. For each item: parse the complaint, ground
  it in the current repo via a read-only Explore subagent, reach a verdict
  (bug / QoL-feature / not-a-bug / defer / investigation), then file one rich GH
  issue with file:line findings. When sourced from Basecamp, comment the issue URL
  back on the card and move it to a triaged column. Use when the user says
  "/triage", pastes tester feedback, points at a Basecamp feedback column, or says
  "go through this feedback", "open issues from this".
---

# Triage

Convert unsorted feedback into curated GitHub issues, one item at a time.

Goal: every actionable piece of feedback becomes a focused issue a cloud agent
can pick up cold — grounded in real `file:line` refs, with a clear verdict, so
nobody re-briefs it later. Issues land in the **current repo** so a
GitHub-connected agent can auto-pick-up and `/one-shot` them.

## When to use

- User pastes a tester message + screenshot(s) and wants it triaged.
- User points at a **Basecamp feedback column** ("triage my inbox", "/triage")
  in a repo whose Basecamp project is wired via `.basecamp/config.json`.
- User says "/triage", "go through this feedback", "open issues from this".
- A batch of feedback items arrives to process one by one.

Skip when the user already knows the exact fix and just wants it done → just do
the work (or use `/one-shot`). Triage is for *unsorted* feedback that needs a
fixable-vs-not call first.

## Input modes

Triage grounds and files identically regardless of source — only how items
**arrive** differs. Pick the mode from context:

| Mode | Trigger | Source |
|------|---------|--------|
| **pasted** | user pastes a message and/or screenshots | the message + attached images |
| **basecamp** | bare `/triage` in a repo with `.basecamp/config.json`, or "triage my Basecamp inbox" | cards in a named feedback/inbox column |

`/triage --from basecamp` forces basecamp mode; `--from pasted` forces pasted.
If a repo has a Basecamp config but the user also pasted text, the pasted text
wins (it's the more specific signal).

### Basecamp mode — pulling the inbox

The Basecamp project is resolved from `.basecamp/config.json` (so `--in` can be
omitted). Process:

1. **Find the inbox column.** `basecamp cards columns --json` (add
   `--card-table <id>` if the project has multiple tables — the ambiguity error
   names them). Pick the feedback/triage/inbox column; if the name is ambiguous,
   ask which column once, then remember it for the batch.
2. **List its cards.** `basecamp cards list --column <id> --json` — each card is
   one feedback item. Process them **one at a time**, oldest first.
3. **Read the card + its screenshots.**
   `basecamp cards show <card_id> --download-attachments --json` — the
   `content_attachments` / `description_attachments` entries come back with a
   local `path`; Read those images the same way you'd read a pasted screenshot.
4. Feed the card title + body + images into the loop below exactly as if pasted.

## The loop (per feedback item)

If several items are queued at once, ground them **in parallel** (one Explore
agent per item) — they're independent. Filing/commenting stays sequential.

### 1. Parse

Restate the complaint/request in one or two crisp lines. Name the exact screen /
feature. Separate the *symptom* (what the tester saw) from the *ask* (what they
want). Note any positive signal (e.g. "send was fast") so it isn't mistaken for
a bug. Strip duplicate or stretch sub-asks the tester themselves hedged on
("IDK", "maybe", "defer to X").

### 2. Ground (read-only Explore subagent)

First, orient to the **current repo's** stack and conventions — read its
`CLAUDE.md` / `AGENTS.md` / `docs/` so the grounding and the issue speak the
repo's language (framework, layering rules, test/lint gates). Don't assume a
stack; discover it.

Then spawn an `Explore` agent to find, with `file:line`:
- the module / component / template rendering the screen or feature
- the data source (which API / context / query feeds it)
- whether the needed data/fields already exist or are dropped upstream
- existing patterns to reuse (tooltips, native collapse, relative-time helpers,
  client hooks, etc.)

Cap the report: **"under ~280 words, bullets only, file:line refs, no code
dumps."** Never let the agent dump a transcript into the main thread.

This step is what makes the issue agent-pickup-ready. Don't skip it.

### 3. Verdict

Classify before writing anything:

| Verdict | Meaning | Action |
|---------|---------|--------|
| **bug** | code is wrong / data dropped / broken interaction | file `bug` issue with root cause |
| **QoL / feature** | works, tester wants an improvement | file `enhancement` issue |
| **not-a-bug** | expected behaviour / data-source limitation | file a small issue that *documents/discloses* it (tooltip, link) or close-worthy — say so |
| **defer** | needs a product decision ("ask @X") | file lightweight `needs input` issue, name the decider, propose resolution, do NOT build |
| **investigation** | answer needs runtime data, fuzzy payoff | file an investigation issue with hypotheses + next steps; do NOT blind-fix |

**Density gate (important).** Before committing to a fix, ask: can this be
resolved from code, or does it need live data / a runtime diff with uncertain
payoff? If the latter → it's an investigation, not a fix. Watch for rabbit
holes (e.g. "count differs from external tool by 0.1%" — usually the external
tool aggregates more sources; document, don't chase).

If scope is genuinely ambiguous (e.g. QoL-only vs build a big feature), use
`AskUserQuestion` with a recommended option first. Otherwise pick the obvious
call and proceed — say which.

### 4. File the issue

Use the template below. Write the body to a temp file and create via `gh` on the
**current repo** (no `--repo` flag needed — `gh` uses the repo you're in):

```
gh issue create --title "<conventional title>" \
  --label <bug|enhancement> [--label <extra>] --body-file <tmpfile>
```

Labels: `bug` for defects, `enhancement` for features/QoL/investigation. Add a
repo-specific label (e.g. `design-conformance`) only after verifying it exists —
`gh label list`. Create a missing label with `gh label create` rather than
silently dropping it.

### 5. Close the loop on the card (basecamp mode only)

After the issue is filed, link it back and clear the board:

```
basecamp comment <card_id> "🔗 Filed: <issue-url>" --in <project>
basecamp cards move <card_id> --to "<Triaged column>" --card-table <table_id>
```

Resolve the Triaged/In-progress column id once (`basecamp cards columns`) and
reuse it. If no such column exists, comment only and say so — don't invent board
structure.

### 6. Report

One terse line back: verdict + issue URL (+ card moved, in basecamp mode). Keep a
running tally across the batch.

## Issue body template

```markdown
## Workstream
<layer/area, in the repo's own vocabulary>
<for investigations/defers, add a `## Type` line: bug | investigation | needs product input>

## Context
<the tester's complaint, parsed. symptom + ask. positive signals noted.
 in basecamp mode, link the source card URL.>

## Findings (code inspection)
<grounded file:line bullets from the Explore agent — root cause for bugs,
 data availability for features. This is what lets an agent start cold.>

## Scope
<numbered, concrete steps with file:line anchors and which existing pattern to reuse>

## Acceptance
<observable outcomes. ALWAYS include the repo's own build + test gates
 (discovered from CLAUDE.md/CI), and tests extended where logic changes.>

## Out of scope
<the stretch sub-asks the tester hedged on; sibling concerns split off>

## PR split
<single small PR | split A/B with the bigger win first>
```

## Bake the repo's own conventions into every issue

Don't hardcode a stack — read it from the target repo and mirror it:

- **Acceptance gates** come from the repo's CI / CLAUDE.md (e.g. a warnings-as-
  errors compile step, a lint task, a typecheck) — not a fixed command. Find the
  real gate and cite it so CI passes on first push.
- **Layering / architecture rules** stated in the repo (e.g. "web layer goes
  through context X, never Y directly") must be respected in the Scope steps.
- **Reuse existing patterns over new abstractions** — point at the concrete
  helper/component the repo already has (tooltip attr, native `<details>`,
  a format helper, a client hook) rather than proposing a fresh one.

## Anti-patterns

- Filing an issue with no `file:line` grounding → agent has to re-discover everything.
- Blind-fixing an investigation item without the runtime diff.
- Bundling a tester's hedged stretch ask ("maybe corp assists? IDK") into the
  core issue → scope creep. Split or mark out-of-scope.
- Matching an external tool's number exactly when it aggregates more sources —
  document the difference instead.
- Letting the Explore agent dump a transcript into the main thread (cap it).
- Assuming a stack. Read the repo's CLAUDE.md/AGENTS.md before grounding.
- **Basecamp mode:** filing the issue but forgetting to comment + move the card —
  the board silently drifts out of sync. Always close the loop (step 5).
- **Basecamp mode:** re-triaging cards already moved to the Triaged column. Only
  process the inbox column.

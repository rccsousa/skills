---
name: issue-enriching
description: >
  Turn a thin GitHub issue into an agent-pickup-ready one — ground it in the repo
  via a read-only Explore subagent, reach a verdict, and append a delimited
  `## Agent brief` (findings with file:line, scope, acceptance, out-of-scope) to
  the issue body without touching the original text. Transitions nightshift labels
  so a downstream `/one-shot` can start cold. Use when the user says
  "/issue-enriching", "enrich issue 42", "make this issue agent-ready", or as
  nightshift's phase 1. For raw feedback that isn't an issue yet, use /triage.
disable-model-invocation: true
metadata:
  version: 0.1.0
---

# Issue Enriching

One issue in, same issue out — grounded.

`/triage` creates issues from raw feedback. This **rewrites an existing issue** so
an agent can pick it up cold. Same grounding core, different source and sink:

| | source | sink |
|---|---|---|
| `/triage` | pasted message / Basecamp card | `gh issue create` |
| `/issue-enriching` | `gh issue view <n>` | `gh issue edit <n>` — brief appended |

The shared middle — orient, Explore-ground, verdict table, body sections, repo
conventions, anti-patterns — is `~/.claude/skills/_shared/issue-grounding.md`.
**Read it.** This file only covers what's different.

## Invocation

```
/issue-enriching <issue-number> [<issue-number>...]
/issue-enriching                # all issues labelled `nightshift`
```

Runs against the **current repo** — `gh` resolves it, no `--repo` needed.

## Per issue

### 1. Read the issue

```bash
gh issue view <n> --json number,title,body,labels,comments,url
```

Read comments too — clarifications and "actually it's X" corrections live there,
and they routinely contradict the body. If the issue or a comment references
images, fetch and read them.

**Already enriched?** If the body contains `<!-- nightshift:brief:start`, this is a
re-run. Re-ground from scratch and replace everything between the delimiters. Never
stack a second brief.

### 2. Parse

Restate in one or two crisp lines. Separate the *symptom* from the *ask*. Note
positive signals so they aren't mistaken for defects. Strip sub-asks the author
themselves hedged on ("IDK", "maybe", "defer to X") — those become Out of scope.

### 3. Ground

`_shared/issue-grounding.md` §1–2. Read the repo's `CLAUDE.md`/`AGENTS.md` first,
then one capped read-only `Explore` agent (~280 words, bullets, `file:line`, no
code dumps, `run_in_background: false`).

Enriching several issues at once: ground them **in parallel** — several `Agent`
calls in one message. They're independent. Writing back stays sequential.

### 4. Verdict

`_shared/issue-grounding.md` §3, including the density gate.

**Never ask the user.** This skill runs unattended inside nightshift. An ambiguous
scope is not a question — it's a `defer` verdict with the ambiguity written down.

### 5. Write the brief back

Original body stays **verbatim**. Append (or replace between delimiters):

```markdown
<!-- nightshift:brief:start v1 <YYYY-MM-DD> -->
## Agent brief

**Verdict:** bug | QoL/feature | not-a-bug | defer | investigation

### Findings (code inspection)
<file:line bullets — root cause for bugs, data availability for features>

### Scope
<numbered, concrete steps with file:line anchors and the existing pattern to reuse>

### Acceptance
<observable outcomes + the repo's real build/test gates, discovered not assumed>

### Out of scope
<hedged stretch asks; sibling concerns split off>

### PR split
<single small PR | split A/B with the bigger win first>

### Nightshift scope
<the subset ONE unattended session should implement — see below>
<!-- nightshift:brief:end -->
```

**`### Nightshift scope` is mandatory and load-bearing.** An unattended session
implements exactly what this line says, nothing more. Write one of:

- `full issue` — the whole scope fits one PR.
- `part A only — <one line>` — the split's first part. Say plainly which numbered
  Scope steps are in and which are deferred to a follow-up issue.
- `none — <reason>` — too large, or the first part still needs a human. Pair this
  with the `nightshift-blocked` label.

Bias toward the smallest coherent slice. A session handed an A/B split with no
guidance builds both halves into one unreviewable PR, which is the failure this
line exists to prevent.

**Flag core-path work here too.** If the smallest slice still requires a
migration, a CI/workflow change, an auth change, or a lockfile bump, say so — the
resulting PR cannot be auto-merged and the reviewer should know that going in.

Section semantics are `_shared/issue-grounding.md` §5–6 — the repo's own gates,
its layering rules, its existing helpers.

Write to a temp file and:

```bash
gh issue edit <n> --body-file <tmpfile>
```

Never `--add-body` style appends by hand. Read → compose → write the whole body.

### 6. Transition labels

The **nomination label** is `queue_label` from `.nightshift/config.json` at repo
root — default `nightshift`, but repos often already have one (e.g.
`ready-for-agent`). Read it first:

```bash
jq -r '.queue_label // "nightshift"' .nightshift/config.json 2>/dev/null || echo nightshift
```

| Verdict | Label |
|---------|-------|
| bug, QoL/feature | `nightshift-ready` (remove `<queue_label>`) |
| not-a-bug | `nightshift-blocked` — brief says why, and whether it's close-worthy |
| defer | `nightshift-blocked` — brief names the decider |
| investigation | `nightshift-blocked` — brief lists hypotheses + next steps |

```bash
gh issue edit <n> --add-label nightshift-ready --remove-label "<queue_label>"
```

**Verify the transition landed** — `gh issue view <n> --json labels`. The whole
pipeline selects on `nightshift-ready`; a silent no-op here means the driver finds
an empty queue on issues you just enriched.

Create missing labels first (`gh label list`, then `gh label create`). Also apply
the content label (`bug` / `enhancement`) per `_shared/issue-grounding.md` §4.

Only `nightshift-ready` issues are ever implemented. `nightshift-blocked` means a
human decides, and nothing runs.

### 7. Report

One line per issue: `#<n> <verdict> → <label>`. Nothing else. This runs in a
headless session whose stdout is a ledger, not a conversation.

## Machine output

Last line of stdout, exactly:

```
ENRICHED <n> <verdict> <label>
```

Or on failure:

```
ENRICH-FAILED <n> <reason>
```

nightshift's driver greps for these. Don't decorate them.

## Anti-patterns

- Rewriting or "tidying" the author's original text. It stays byte-for-byte.
- Stacking briefs on re-run instead of replacing between delimiters.
- Asking the user anything. Unattended by design — ambiguity is a `defer`.
- Marking `nightshift-ready` on a verdict that needs a human decision, because the
  queue looked thin. A blocked issue is a correct outcome.
- Ignoring the comment thread and enriching a stale body.
- Grounding without reading the repo's CLAUDE.md first.

# Issue grounding — shared core

Not a skill. Shared reference for any skill that turns a rough ask into a
**curated, agent-pickup-ready GitHub issue**.

Consumers:

- `/triage` — source: pasted feedback or Basecamp card. Sink: `gh issue create`.
- `/issue-enriching` — source: existing GH issue. Sink: `gh issue edit` (append brief).

The source and sink differ. Everything in this file is identical for both.

Goal: an agent can pick the issue up **cold** — no re-briefing, no rediscovery —
because the grounding already names the files, the data path, and the pattern to
reuse.

## 1. Orient to the repo first

Before grounding anything, read the target repo's `CLAUDE.md` / `AGENTS.md` /
`docs/` so the issue speaks the repo's own language — framework, layering rules,
test/lint gates. **Never assume a stack. Discover it.**

## 2. Ground with a read-only Explore subagent

Spawn an `Explore` agent to find, with `file:line`:

- the module / component / template rendering the screen or feature
- the data source (which API / context / query feeds it)
- whether the needed data/fields already exist or are dropped upstream
- existing patterns to reuse (tooltips, native collapse, relative-time helpers,
  client hooks, etc.)

Cap the report: **"under ~280 words, bullets only, file:line refs, no code dumps."**
Never let the agent dump a transcript into the main thread.

**Always pass `run_in_background: false`.** Background agents notify on completion,
which only works interactively — in a headless run (CI, cron, `claude -p`,
claude-code-action) the notification never arrives, the session ends mid-item, and
the work is left half-done. Never poll a background agent with `Monitor` /
`TaskList` / sleeps / no-op Bash calls.

This step is what makes the issue agent-pickup-ready. Don't skip it.

## 3. Verdict

Classify before writing anything:

| Verdict | Meaning | Action |
|---------|---------|--------|
| **bug** | code is wrong / data dropped / broken interaction | `bug` — file/record root cause |
| **QoL / feature** | works, asker wants an improvement | `enhancement` |
| **not-a-bug** | expected behaviour / data-source limitation | document or disclose it (tooltip, link) — or say it's close-worthy |
| **defer** | needs a product decision ("ask @X") | lightweight `needs input`; name the decider, propose a resolution, do NOT build |
| **investigation** | answer needs runtime data, fuzzy payoff | hypotheses + next steps; do NOT blind-fix |

**Density gate (important).** Before committing to a fix, ask: can this be resolved
from code, or does it need live data / a runtime diff with uncertain payoff? If the
latter → it's an investigation, not a fix. Watch for rabbit holes (e.g. "count
differs from external tool by 0.1%" — usually the external tool aggregates more
sources; document, don't chase).

## 4. Labels

`bug` for defects, `enhancement` for features/QoL/investigation. Add a repo-specific
label only after verifying it exists (`gh label list`); create a missing one with
`gh label create` rather than silently dropping it.

## 5. Issue body template

```markdown
## Workstream
<layer/area, in the repo's own vocabulary>
<for investigations/defers, add a `## Type` line: bug | investigation | needs product input>

## Context
<the complaint, parsed. symptom + ask. positive signals noted.
 link the source (Basecamp card, thread) if there is one.>

## Findings (code inspection)
<grounded file:line bullets from the Explore agent — root cause for bugs,
 data availability for features. This is what lets an agent start cold.>

## Scope
<numbered, concrete steps with file:line anchors and which existing pattern to reuse>

## Acceptance
<observable outcomes. ALWAYS include the repo's own build + test gates
 (discovered from CLAUDE.md/CI), and tests extended where logic changes.>

## Out of scope
<the stretch sub-asks the asker hedged on; sibling concerns split off>

## PR split
<single small PR | split A/B with the bigger win first>
```

## 6. Bake the repo's own conventions in

- **Acceptance gates** come from the repo's CI / CLAUDE.md (a warnings-as-errors
  compile step, a lint task, a typecheck) — not a fixed command. Find the real gate
  and cite it so CI passes on first push.
- **Layering / architecture rules** stated in the repo ("web layer goes through
  context X, never Y directly") must be respected in the Scope steps.
- **Reuse existing patterns over new abstractions** — point at the concrete
  helper/component the repo already has, not a fresh one.

## 7. Anti-patterns

- No `file:line` grounding → the agent has to rediscover everything.
- Blind-fixing an investigation item without the runtime diff.
- Bundling a hedged stretch ask ("maybe corp assists? IDK") into the core scope →
  scope creep. Split or mark out-of-scope.
- Matching an external tool's number exactly when it aggregates more sources —
  document the difference instead.
- Letting the Explore agent dump a transcript into the main thread (cap it).
- Assuming a stack. Read the repo's CLAUDE.md/AGENTS.md before grounding.

---
name: council-of-agents
description: >
  Parallel multi-lens planning amplifier. Dispatch 3-5 subagents in parallel — each
  with one lens (architecture, UX, security, ops, persistence, etc.) — and synthesise
  their reports into a unified design brief. Use before writing plans when scope is
  fuzzy, multi-stakeholder, or spans multiple concerns.
---

# Council of Agents

Multi-lens planning amplifier. Each council member is a subagent assigned a single
lens. Members run in parallel against the same scope brief; a synthesis agent
merges their reports into a unified design brief that feeds the plan phase.

Stronger than a single grilling — surfaces concerns one lens would miss. Cheaper
than a full brainstorming round-trip when scope is roughly known but architecture
calls are open.

## When to use

- Scope is fuzzy or multi-stakeholder
- Two or more concerns intersect (backend × UX, security × perf, domain × ops)
- A single planning round would likely miss a lens
- Pre-plan amplifier before `writing-plans` on a non-trivial feature
- Always-on inside `one-shot --mode=grill`

## When to skip

- Single-PR tech debt
- Trivial edits / fixes / renames
- Scope is already nailed down — go straight to the plan

## Council size

- **3 lenses** for narrow / focused work
- **5 lenses** for broad / multi-concern work
- **>5** = diminishing returns + synthesis overhead. Pick the most relevant lenses.

## Default lens menu

Pick a subset matching the feature surface:

- **Architecture** — module boundaries, supervision, facade rules, code layout
- **UX / frontend** — interaction flow, mobile, accessibility, component reuse
- **Security** — authn/authz, XSS, CSRF, token handling, sanitisation
- **Domain** — project-specific semantics, business rules, invariants
- **Ops / observability** — telemetry, metrics, alerting, deploy path
- **Persistence** — data model, migrations, idempotency, eventual consistency
- **Test strategy** — what to TDD, where to mock, fixtures, demo fallback

Add domain-specific lenses ad-hoc (e.g. "i18n", "perf", "API versioning",
"compliance").

## Procedure

1. **Scope brief.** Write 3-5 bullets: what the feature is, what's known, what's open.
   Reuse verbatim across all member prompts.
2. **Pick lenses** — 3-5 from the menu.
3. **Dispatch in parallel** — single message, multiple Agent calls. One agent per lens.
   - Model: Sonnet (lenses are focused, not ambiguous)
   - No worktree isolation — members are read-only researchers
   - Each prompt: scope brief + lens charter + file paths + output template + 250-word cap
4. **Wait for all returns**, then **dispatch one synthesis agent** that reads every
   member report + produces a unified design brief.
5. **Surface synthesis to user** for approval / amendment.
6. **Approved brief → plan phase** (`writing-plans` or equivalent).

## Member prompt template

```
You are a council member with the [LENS] lens on feature [FEATURE].
Do not opine outside your lens — other lenses are covered separately.

## Scope brief
[paste shared scope brief verbatim]

## Your lens
[2-3 sentences describing what falls under this lens for this feature]

## Files to ground in
- path/to/file — why
- path/to/other — why

## Output (≤250 words, this exact structure, no preamble)

### Scope rec
- In v1: ...
- Deferred: ...

### Lens-specific calls
- decision 1 (with rationale, one line)
- decision 2

### Risks / unknowns
- q1
- q2

### Effort within lens
- chunk: S / M / L

### Dependencies on other lenses
- lens X must agree on Y
```

## Synthesis prompt template

```
You are the synthesiser. Read all N council member reports below.
Produce a unified design brief at plans/<feature>-design-brief.md.

## Member reports
[paste each report verbatim, labeled by lens]

## Brief structure (≤600 words)
1. **Scope** — in v1 / deferred. Resolve disagreements between lenses explicitly.
2. **Architecture decisions** — the locked calls.
3. **Risk register** — top risks, owner-lens, mitigation if known.
4. **Open questions for user** — only the ones the council could not resolve.
5. **Effort estimate** — S/M/L per major chunk.
6. **Conflicts between lenses** — explicit list. Do NOT paper over disagreements.
```

## Failure modes

- **Lens overlap** — two members opining on the same call. Re-dispatch the looser-fit
  lens with stricter scope.
- **Kitchen-sink response** — member ignored their lens, tried to cover everything.
  Re-dispatch with tighter charter + smaller word cap.
- **Synthesis suppressing disagreement** — design brief MUST call out conflicts. If
  synthesis says "all lenses agreed" check whether dissent was dropped.
- **Wrong size council** — 3 when 5 was needed (gaps in brief), 5 when 3 was enough
  (synthesis bloat). Adjust next round.

## Pipeline integration

```
council → plan → (PRD → issues, optional) → implement → review → fix → ready-to-merge
```

Front-phase amplifier for `one-shot`. Run before the plan phase on non-trivial work.

## Output style — caveman ultra (under-the-hood)

Council members + synthesiser operate in caveman ultra mode for their generated
outputs. Token saver, not presentation choice.

**Applies to:** member reports (scope rec, decisions, risks bullets), synthesis
design brief, summary surfaced to user.

**Does NOT apply to:** code references, file paths, identifiers, quoted plan
tasks, error / halt messages.

**Rules:**

- Drop articles, filler
- Fragments OK
- Short synonyms (DB / auth / fn / req / res / impl)
- Arrows for causality (X → Y)
- One word when one word suffices

Example member bullet:

- Normal: "The authentication module should be refactored to use a token-based approach"
- Caveman ultra: "auth module → token-based"

## Cost notes

- 5 members × 250 words ≈ 1250 words of return — fits comfortably in synthesis context.
- Synthesis output: 600 words. Manageable in orchestrator main session.
- Members: Sonnet. Synthesis: Sonnet. Escalate synthesis to Opus only when conflicts
  are deep + need architecture-level adjudication.

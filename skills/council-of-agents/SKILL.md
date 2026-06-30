---
name: council-of-agents
license: MIT
description: Parallel multi-lens planning. Dispatch N subagents, each with one lens (architecture, UX, security, domain, ops, persistence, test). Synthesize into a unified design brief that feeds writing-plans. Use before plans when scope is fuzzy or multi-stakeholder.
user-invocable: false
---

# Council of Agents

## What

Multi-lens planning amplifier. Each "council member" is a subagent assigned a single lens (architecture, UX, security, domain, ops, persistence, test strategy). Members run in parallel against the same scope brief; a synthesis agent merges their reports into a unified design brief that feeds `writing-plans`.

Stronger than a single grilling — surfaces concerns one lens would miss. Cheaper than a brainstorming round-trip when scope is roughly known but architecture / scoping calls are open.

## When to invoke

- Scope is fuzzy or multi-stakeholder
- Two or more concerns intersect (backend × UX, security × perf, domain × ops)
- A single planning grilling would likely miss a lens
- Pre-planning amplifier before `writing-plans` on a non-trivial feature

## When to skip

- Single-PR tech debt
- Trivial edits / fixes / renames
- Scope is already nailed down — go straight to `writing-plans`

## Council size

- **3 lenses** for narrow / focused work
- **5 lenses** for broad / multi-concern work
- **>5** = diminishing returns + synthesis overhead. Pick the most relevant lenses for the feature.

## Default lens menu

Pick a subset matching the feature surface:

- **Architecture** — module boundaries, OTP supervision, facade rules, code layout
- **UX / LiveView** — interaction flow, mobile/PWA, accessibility, component reuse
- **Security** — auth scopes, XSS, CSRF, token handling, content sanitization
- **Domain** — project-specific semantics (e.g. ESI rate limits, EVE mail rules)
- **Ops / observability** — supervision, telemetry, Oban, error reporting, demo path
- **Persistence** — data model, migrations, idempotency, eventual consistency
- **Test strategy** — what to TDD, where to mock, fixtures, demo fallback

Add domain-specific lenses ad-hoc when needed (e.g. "i18n", "perf", "API versioning").

## Procedure

1. **Scope brief.** Write 3-5 bullets describing what the feature is, what's known, what's open. Reuse this verbatim across all member prompts.
2. **Pick lenses** — 3-5 from the menu.
3. **Dispatch in parallel** — single message, multiple Agent calls. One agent per lens.
   - Model: `sonnet` (lenses are focused, not ambiguous)
   - No `isolation: "worktree"` needed — council members are read-only researchers, not writers
   - Each prompt: scope brief + lens charter + file paths to ground in + output template + word cap (250)
4. **Wait for all returns**, then **dispatch one synthesis agent** per scope (sonnet) that reads every member report and produces a unified design brief.
5. **Surface synthesis to user** for approval / amendment.
6. **Approved brief → `writing-plans`** to produce the implementation plan.

## Member prompt template

```
You are a council member with the [LENS] lens on feature [FEATURE].
Do not opine outside your lens — other lenses are covered separately.

## Scope brief
[verbatim — paste the shared scope brief]

## Your lens
[2-3 sentences describing what falls under this lens for this feature]

## Files to ground in
- path/to/file.ex — why
- path/to/other.ex — why

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
You are the synthesizer. Read all N council member reports below.
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

- **Lens overlap** — two members opining on the same call. Re-dispatch the looser-fit lens with stricter scope.
- **Kitchen-sink response** — member ignored their lens and tried to cover everything. Re-dispatch with tighter charter + smaller word cap.
- **Synthesis suppressing disagreement** — design brief MUST call out conflicts. If synthesis says "all lenses agreed" check whether dissent was just dropped.
- **Wrong size council** — 3 when 5 was needed (gaps in brief), 5 when 3 was enough (synthesis bloat). Adjust next round.

## Pipeline integration

```
council → plan (writing-plans) → PRD (to-prd, optional) → issues (to-issues, optional) → implement → review → fix → merge
```

The council is a front-phase amplifier for `feature-flow`. Run before `writing-plans` when the feature warrants multi-lens scrutiny.

## Cost notes

- 5 members × 250 words ≈ 1250 words of return — fits comfortably in synthesis context.
- Synthesis output: 600 words. Manageable in orchestrator main session.
- Members: sonnet. Synthesis: sonnet. Escalate synthesis to opus only when conflicts are deep and need architecture-level adjudication.

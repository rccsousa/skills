---
name: verify-review-findings
description: Adversarially verify code-review findings against source + runtime BEFORE presenting them with a severity. Each finding is traced to code and empirically checked; unproven ones are downgraded or refuted. Use after any review that fanned out subagents, before sending findings to a client/team/PR, or whenever a finding's severity is reviewer judgement not proven fact. Triggers - "/verify-review-findings", "verify these findings", "are these findings real?", "check before I post".
disable-model-invocation: true
---

# verify-review-findings

A verification gate between *finding* and *reporting*. Code reviewers — especially fanned-out subagents — pattern-match on smells and assert consequences they never traced. This skill makes each finding earn its severity.

**Core principle:** A finding is a hypothesis until traced to source and, where behaviour depends on a library/runtime contract, confirmed by running it. Present evidence, not assertions.

## Why this exists

On the My Finances audit, 5 parallel reviewers produced 10 🟠 findings. Verified one by one, **8 of 10 collapsed** — wrong worked examples, unreachable branches, correct-by-design behaviour mistaken for bugs. Raw severities sent to the team would have been refuted in one reply. The cost is credibility, highest on external audits where the brief is "guard, not contributor." See memory [[verify-review-findings-before-reporting]].

## When to invoke

**Mandatory:**
- After any review that fanned out subagents (their findings are unverified by construction)
- Before sending findings to a client, team, or PR thread
- On an audit/external review where credibility is the deliverable

**Skip:** trivial findings where the fix is obviously correct and cheaper than the verification (typo, unused import).

## The gate — per finding

For every finding above "nit", do all four:

1. **Trace to source.** Follow the full path — route → controller → function → schema → DB. Confirm the cited line does what the finding says, and that the bad path is *reachable* (not collapsed/guarded upstream). Many findings die here: the branch has no reachable producer, or a sibling clause already handles it.

2. **Run the contract.** When the claim depends on how a library/language/runtime behaves — `Float.to_string`, Ecto/ORM casts, framework status mapping, job-queue semantics (Oban snooze), float vs Decimal — **do not trust memory**. Run a minimal snippet (`elixir`/`node`/`mix run`, `Mix.install` for a single dep) or read the library's own docs via context7. Memory is where false findings come from.

3. **Classify the outcome:**
   - **Stands** — traced + (if relevant) empirically confirmed. Keep severity.
   - **Downgrade** — real but milder than claimed (minor/hygiene, by-design, self-documented). Lower severity, say why.
   - **Refute** — the claim is false or the path is unreachable. Mark closed, show the disproof.

4. **Attach evidence.** A table of cast results, a round-trip demo, the doc quote, the upstream clause that collapses the error. The reader should be able to re-run it.

## Output

Reconcile the report in place — don't append a contradictory addendum:
- Update each finding's severity badge and add a one-line verification verdict (`✅ verified` / `🟡 downgraded — <why>` / `✅ refuted — <disproof>`).
- Fix any summary table / top-line verdict to match the survivors.
- Add an honest self-correction note if first-pass counts were inflated, so raw counts don't mislead.
- State verification depth explicitly: which findings were traced+run, which remain reviewer judgement.

## Red flags

- Presenting a severity you haven't traced to a reachable code path.
- A worked example you reasoned out but never executed (the `0.1 → 0.30000000000000004` trap: true for arithmetic, false for a literal).
- "Silently truncates / corrupts / masks" claims — these almost always hinge on a runtime contract; run it.
- Leaving the summary table at inflated counts after downgrading the bodies.

## Pairs with

- `deep-audit` — wraps this gate inside the full external-audit loop (read-only posture → fan-out → this gate → local report). When auditing code you don't own, start there; it calls this.
- `surgical-review` / `request-review` / fanned-out code-reviewer subagents — they *produce* findings; this *gates* them.
- `context7-mcp` for library-contract checks.

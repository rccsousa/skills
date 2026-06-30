---
name: red-team-findings
description: Hand a verified set of audit findings to one fresh, independent opus agent whose only job is to REFUTE them — prove false-positive, wrong-severity, or unreachable — then hunt what the audit missed and challenge its "verified clean" claims. A second adversarial layer after self-verification, because confirmation bias survives first-party tracing. Use as the red-team gate inside deep-audit (step 4.5), or standalone before sending any high-stakes findings out. Triggers - "/red-team-findings", "red-team this audit", "adversarial pass on these findings", "try to break my findings".
disable-model-invocation: true
---

# red-team-findings

A second adversarial gate, *after* self-verification. `verify-review-findings` makes you trace your own findings — but you trace them looking to confirm. A fresh agent that has never seen your reasoning, told to **disprove**, catches what self-verification structurally can't.

**Core principle:** The auditor who found it cannot impartially red-team it. Independence is the whole value — a blind, adversarial, strong-model second opinion on the *survivor set*, not a re-run of the same trace.

## When to invoke

- Inside `deep-audit` as **step 4.5**, after the VERIFY gate has produced surviving findings and before RECONCILE writes the report.
- Standalone before sending any high-stakes findings to a client/team/PR, especially an external audit where a refuted finding costs credibility.

**Skip** for a quick self-review you're not publishing, or when there's a single trivial finding whose fix is cheaper than the pass.

## How it differs from `verify-review-findings`

| | `verify-review-findings` | `red-team-findings` |
|---|---|---|
| Who | you (first-party) | a fresh independent agent |
| Stance | trace each finding to confirm/refute | *try to break* each finding |
| Input | the raw fan-out findings | the **survivor set** (post-verify) |
| Also does | — | hunts misses + challenges "verified clean" claims |

Run verify first, red-team second. They stack; the red-team is not a replacement.

## The pass

1. **One agent, opus-tier, independent.** Spawn a single `general-purpose` Agent with `model: "opus"` (the strongest model — this is the credibility backstop). It must be blind to the per-cluster reasoning: give it the repo path, the diff range (`<base>...<branch>`), and the **survivor list** as `severity + file:line + one-line claim` — **not** the draft report's prose (prose leaks your conclusions and biases it toward agreement).

2. **Frame it to disprove.** Verbatim spine for the prompt:
   > "You are an adversarial second auditor. NOT our repo — READ ONLY, do not edit/write/commit. For EACH finding, independently trace to source and try hard to prove it WRONG — false positive, wrong severity, or not actually reachable. A finding only survives if you can reproduce the reasoning from the code. Default to skepticism."
   Then, as separate tasks: **hunt what the audit MISSED** (new findings), and **re-examine each 'verified clean' claim for over-confidence** (is every route really inside the auth pipeline? does the serializer really omit the PII group? is the magic-byte check real?).

3. **Demand a structured, capped verdict.** One line per finding:
   `#N VERDICT(confirmed | downgrade-to-X | REFUTED | overstated) — evidence (file:line + what was seen)`.
   Then a `MISSED` section (severity + `file:line` + why) and a one-line take on whether the top-line verdict still holds. Cap ~400 words, so it doesn't dump a transcript into the orchestrator.

4. **Fold the result in — weigh it, don't rubber-stamp it.** The red-team is another *input*, not an oracle. Drop/downgrade what it refutes or calls overstated; promote what it confirms; adopt a MISSED finding only after it itself traces to a reachable source path (re-verify before adding — a red-team miss is a hypothesis too). A material new finding is a fresh VERIFY cycle, not an instant addition.

5. **One pass is enough** unless it lands a material new finding. Don't loop red-teams for diminishing nits.

## Output

Feeds RECONCILE — the report should reflect what the pass changed:
- Each refute/downgrade applied to its finding's badge + verdict; refuted findings removed (or marked closed with the disproof).
- Adopted misses added with their own trace evidence.
- Top-line verdict re-derived from the surviving set.
- A one-line note that an adversarial pass ran and a summary of net change (e.g. "dropped 1, downgraded 3, elevated 1, added 1") — net-shrinking an audit is the right direction for credibility.

## Red flags

- Feeding the agent the polished report prose instead of the bare survivor list — it'll agree with your framing.
- Using a weak/cheap model — the backstop must be at least as strong as the auditor.
- Treating the red-team as authoritative — adopting a MISSED finding without tracing it yourself.
- Re-using one of the original cluster reviewers (not independent — it already committed to its findings).

## Pairs with

- `deep-audit` — calls this as step 4.5, between VERIFY and RECONCILE.
- `verify-review-findings` — the first-party gate this stacks on top of; run that first.
- `context7-mcp` for library-contract checks the red-team needs.

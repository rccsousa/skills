---
name: surgical-review
license: MIT
description: Dispatch a strict code-reviewer subagent that enforces strict coding standards — SRP, naming-tells-the-story, no premature abstraction, let-it-fail on internal contracts, terse comments, surgical scope. Use before opening a PR, after a major feature/step, or when stuck.
---

# Surgical Review

Strict code review that enforces strict coding standards beyond the generic "looks good, consider tests" baseline. Catches the failure modes that bite large PR stacks: SRP violations, names that don't tell the story, premature abstraction under context pressure, defensive guards on internal contracts, narrative WHAT-comments.

**Core principle:** A useful review walks the bug scenario, verifies load-bearing assumptions against actual code, and separates blockers from followups. A useless review says "looks good, add more tests."

## When to Invoke

**Mandatory:**
- Before opening a PR (post final-pass refactor sweep)
- After completing a major feature / plan step
- After any non-trivial change to shared infrastructure (auth, DB schema, balance, webhooks)

**Optional but valuable:**
- When stuck — fresh perspective
- Before a refactor — baseline check
- After fixing a complex bug

## How to Dispatch

**1. Get git SHAs:**
```bash
BASE_SHA=$(git rev-parse origin/main)
HEAD_SHA=$(git rev-parse HEAD)
```

**2. Spawn subagent** via the Agent tool with `subagent_type: superpowers:code-reviewer`. Fill the template at `reviewer-prompt.md` and pass it as the prompt.

**Placeholders:**
- `{WHAT_WAS_IMPLEMENTED}` — what was built (1-2 sentences)
- `{BUG_SCENARIO}` — the concrete scenario the change addresses, with real numbers and real code paths. For a feature, replace with "Feature scope: …" and describe the user-facing behavior end-to-end.
- `{LOAD_BEARING_ASSUMPTIONS}` — assumptions the change depends on (reviewer must falsify each against actual code, not trust them).
- `{SURGICAL_SCOPE}` — what the change SHOULD and SHOULD NOT touch. Explicit boundary lets the reviewer flag scope creep.
- `{PLAN_REFERENCE}` — link to plan file, issue tracker ticket, or PR description.
- `{BASE_SHA}` / `{HEAD_SHA}` — git range.
- `{FILES_TO_FOCUS}` — file:line citations for the meaty parts; reviewer reads surrounding handlers/callers, not just the diff.

**3. Act on feedback:**
- **Critical** → block PR, fix immediately
- **Major** → block PR, fix before proceeding
- **Minor / nits** → note in chat, skip by default (only Critical/Major are blockers)
- **Followups** → surface in chat, **never** `gh issue create`
- Push back with reasoning if reviewer is wrong; cite code/tests that prove it.

## What This Review Catches (vs. baseline)

| Failure mode | Caught by |
|---|---|
| `resolveStep0`, `handleThing2`, `processData` | Naming-tells-the-story check |
| Function doing 2+ things (fetch + transform + persist) | SRP check |
| 14k-LOC service file with 300+ LOC functions | File/function size sanity |
| Helper used by only 1-2 callers, options for hypothetical reuse | No-premature-abstraction check |
| `if (account?.id)` after a typed getter that throws on miss | Let-it-fail check |
| `// fetches user from db` above `getUserFromDb()` | Terse-comments check |
| Unrelated cleanup bundled into a surgical fix PR | Surgical-scope check |

## Integration

- Pair with the `codebase-examiner` dispatch — examiner first to gather context, fold its brief into the surgical-review prompt. Keeps the main thread thin.
- Pair with the **final pre-PR refactor pass** — refactor first, then review. Don't review mid-implementation.
- Pair with a **pre-PR comment audit** — delete WHAT-comments before review.

See template: `reviewer-prompt.md`

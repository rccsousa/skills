---
name: maintainability-review
description: Review a PR, diff, or selected code for concrete readability and maintainability improvements, then return a distilled review without applying fixes. Use for /maintainability-review or reviews focused on ease of inspection and safe maintenance. For applied fixes, use an implementation workflow authorized by the user.
---

# Maintainability review

Find changes that make the code easier to inspect and safer to modify. Prefer explicit business steps and visible operational contracts over fewer lines. Review only unless the user also authorizes implementation or posting.

## Scope and evidence

- Accept `/maintainability-review <PR URL|PR number|branch|range|file>` or the current diff. Resolve the intended base and immutable head for Git targets; identify staged and unstaged changes when reviewing local work. Never assume a default branch name.
- Read applicable repository instructions, the complete scoped diff, and enough unchanged callers, helpers, tests, and documentation to understand the contracts. Search for existing business rules before recommending extraction or reuse.
- Keep attention on complexity introduced or materially affected by the change. An existing comment becomes relevant when the change invalidates its contract; unrelated cleanup does not.
- Do not read existing PR reviews before forming the first assessment. If the user supplies another review, assess its claims against the source; do not call that an independent blind pass.
- No automatic fixes, test generation, counterpart invocation, or delegation. For an explicitly requested two-model pass, use [angular-maintainability-review](../SKILL.md), which overrides this single-host execution rule.

## Review lenses

Apply these where they reduce a concrete maintenance cost, not as a checklist of required edits:

- **Named business steps.** Keep orchestration readable top to bottom. Extract cohesive steps such as building a request, validating a beneficiary, or interpreting a response. Group checks for one rule together. Function length alone is not a finding; avoid trivial forwarding helpers and generic validator frameworks.
- **Names and arguments.** Name values by their business meaning and actual return shape. Prefer named objects where same-typed arguments or bare booleans conceal consequential meaning. Make uncertainty, permission scope, and operation phase visible at call sites. Construct response envelopes in one place rather than mutating through their nested internals.
- **Precedence and lifecycle.** Make competing error categories, mismatch-versus-incomplete verdicts, transaction boundaries, and side-effect timing easy to trace. Extraction must preserve existing priority, check order, short-circuiting, errors, and timing. Replacing overwrites with early returns can reverse priority; verify the proposed order explicitly.
- **Rule ownership.** Identify duplicated business policy and name the existing implementation. Distinguish accidental duplication from deployment, sandbox, or dependency boundaries. Where shared implementation is inappropriate, recommend focused shared contract cases only when they protect a demonstrated drift risk. Different envelopes or classifications are not automatically correctness defects.
- **Explicit critical configuration.** Keep short fixed secret mappings, permissions, environment differences, routes, and production conditions directly inspectable. Do not replace them with maps, loops, computed keys, or a framework merely to reduce repetition. Use abstractions when the collection is dynamic or the maintenance benefit is concrete.
- **Limits and documentation.** Name limits that carry an operational contract or must remain synchronized, such as total deadlines and response-size bounds. Avoid blanket constant extraction. Correct stale contract comments. Prefer a better name, type, or named test to explanatory prose; reserve a short pointer comment for a non-local fact that cannot be recovered from the code.

## Distill and reconcile

For each candidate, establish an exact location, the current inspection or change cost, and the smallest behavior-preserving improvement. Do not require a runtime failure to justify a maintainability finding, and do not invent one to raise severity.

Keep only recommendations whose benefit exceeds the added indirection and refactor risk. Merge comments about the same root cause. Drop personal taste, mandatory helper ordering, speculative future flexibility, cosmetic renaming, blanket constants, and abstractions that hide a handful of consequential settings. There is no finding quota.

When converging with another review:

- Verify claims independently of agreement; retain useful unique findings and explain material disagreements.
- Combine overlapping recommendations into one actionable comment, not a union of both lists.
- Preserve intentional behavior and repository conventions. Reject suggestions that reorder checks, change precedence, or broaden the task under the label of readability.
- Treat a code difference as a maintenance risk until a reachable wrong outcome is verified. Report any incidentally discovered correctness defect separately with its own evidence.

## Deliver

Lead with the highest-value recommendations. Each entry contains `file:line`, the concrete maintenance cost, and a scoped fix. Use priorities only when helpful; maintainability suggestions are non-blocking unless the user defines a different gate. Do not manufacture a Critical/High correctness verdict for structural preferences.

State the reviewed snapshot and material evidence limits. Static review is sufficient for structural recommendations; run focused existing tests only when needed to support a behavioral claim or an assertion that a proposed change preserves semantics. Distinguish code inspection, executed validation, and unverified claims. Recheck remote head before delivering a PR review.

If nothing clears the bar, say `No actionable maintainability findings.` Keep the report short. When asked to converge, include only material changes to the earlier assessments and the distilled comments. Draft a postable review only when requested; posting requires user authorization.

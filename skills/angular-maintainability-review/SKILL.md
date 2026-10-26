---
name: angular-maintainability-review
description: Run two independent blind readability and maintainability reviews, host plus counterpart model, then verify and distill the recommendations. Use for /angular-maintainability-review or an explicitly requested angular maintainability review. Use angular-review for its correctness-focused gate.
---

# Angular maintainability review

Apply [maintainability-review](references/maintainability-review.md) through two independent blind passes, then converge once. Load that skill for its review lenses, evidence bar, behavior-preservation constraints, and delivery rules. This wrapper replaces its single-host execution rule, not its scope or quality bar.

## Invocation and snapshot

Accept `/angular-maintainability-review <PR URL|PR number|branch|range|file>` or an explicitly scoped local diff. Honor user choices for base, effort, validation, and output format.

Resolve immutable base/head SHAs for Git targets. For uncommitted work, capture the same staged, unstaged, and explicitly included untracked content for both reviewers; do not let them inspect different snapshots. Reuse a suitable clean review worktree or inspect Git objects for committed targets. Preserve user work; keep review artifacts outside tracked project files.

## Two blind passes

Prepare one neutral evidence packet with the target objective, repository instructions, snapshot identity, full scoped diff, necessary unchanged callers and existing rules, and any relevant validation results or omissions. Exclude prior findings, suspicions, proposed fixes, desired verdicts, and existing GitHub reviews. When the user supplies an existing review, reconcile it after both passes; do not feed it into either blind pass.

Start the host and a fresh isolated counterpart in parallel when available:

- From Codex: the host reviews directly; invoke a fresh non-persistent `claude -p --model claude-opus-5-5 --effort high` session through an available read-only facility.
- From Claude: the host reviews directly; invoke a fresh isolated Codex `gpt-6.1-sol` session at high reasoning effort through an available read-only facility.
- Give both reviewers the same packet and the maintainability skill text. Each returns proposed findings with exact locations, concrete maintenance costs, smallest behavior-preserving fixes, evidence limits, and any incidental correctness claims separately.
- Exactly two first passes. Deny source edits, Git/GitHub writes, external messages, and further reviewer delegation. Neither reviewer sees the other's conclusions until both finish. Retain the host's assessment before opening counterpart output.
- If a pass is unavailable or fails, identify it and report the limitation. Do not silently substitute a model or call a single completed pass a completed angular review.

## Converge

Inspect the source behind every candidate from either pass. Deduplicate by maintenance problem, not line number or wording. Agreement is not proof; a useful finding can come from either reviewer alone.

Keep only changes whose inspection or maintenance benefit exceeds the added indirection and refactor risk. Verify proposed extraction boundaries, priority rules, and behavior-preservation claims. Do not require a runtime failure for a structural recommendation, or elevate a policy difference to a defect without a verified wrong outcome.

Distill the two reviews rather than concatenate them. Reject cosmetic preferences, blanket maps/constants/comments, mandatory helper ordering, and fixes that change semantics under the label of readability. Preserve material disagreements and explain consequential downgrades or dropped claims. No council, third reviewer, peer discussion, or moderator is required.

## Deliver

Return the compact maintainability report with snapshot identity, the highest-value comments, material validation limits, and disagreements that affected the result. Mark provenance as host, counterpart, or both when it aids reconciliation. Recheck a PR's remote head; if it moved, state the reviewed snapshot and do not extend conclusions to the new head.

Maintainability suggestions remain non-blocking unless the user defines another gate. Report verified incidental correctness defects separately; do not import angular-review's correctness verdict/count format into this review. There is no comment quota. If none survive, say `No actionable maintainability findings.`

No implementation or posting follows automatically. Existing explicit authorization still applies; do not request duplicate approval.

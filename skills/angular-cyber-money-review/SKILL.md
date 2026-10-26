---
name: angular-cyber-money-review
description: Run two blind host/counterpart reviews of one PR, branch, or commit range using the cyber-money-review rubric, then reconcile and verify money-movement and cyber findings. Use only when the user explicitly asks for an angular cyber-money review, dual-model payment/security review, or invokes this skill.
---

# Angular cyber money review

Apply the existing angular-review method to the cyber-money-review rubric. Nothing is posted, committed, pushed, or changed without explicit authorization.

## Invocation

`/angular-cyber-money-review <PR number|PR URL|branch|base..head|base...head>` or `$angular-cyber-money-review ...`

Before acting, read [angular-review](references/angular-review.md) and [cyber-money-review](references/cyber-money-review.md) completely. Follow angular-review's exact-target, neutral-packet, two-blind-pass, verification, and delivery rules. This skill adds the requirements below.

## Blind passes

- Both reviewers receive the same immutable base/head, full diff, direct consumers, focused validation, provider evidence, and deployment facts.
- Neither receives existing reviews, suspected defects, desired verdicts, or the other pass's output.
- Both apply every money-movement classification, cyber trust-boundary check, finding threshold, and finding/prerequisite distinction from cyber-money-review.
- From Codex, the counterpart is a fresh read-only `claude -p --model claude-opus-5-5 --effort high` session. Do not substitute Fable, Sonnet, or Haiku. If the counterpart cannot run, report the review incomplete; do not label a single pass angular.
- Deny edits, Git/GitHub writes, external messages, and further reviewer delegation.

Require each pass to return:

- verdict and Critical/High/Medium/Low findings;
- exact `file:line`, reachable state/path, wrong outcome, financial/security impact, fix, and verification;
- the submission-state classification for each money-moving failure path it discusses;
- trust-boundary/capability inventory for each authorization claim;
- activation prerequisites, load-bearing assumptions, evidence gaps, and validation results;
- endpoint audience/publication result when applicable.

## Reconciliation

Reproduce or trace every candidate before keeping it. Deduplicate by root cause and failure scenario. Agreement is not verification.

For disagreements, explicitly record:

- the conflicting claims;
- the evidence that kept, narrowed, downgraded, or withdrew each claim;
- whether the result is a defect, activation prerequisite, hardening note, assumption, or evidence gap.

Do not converge by averaging severity or accepting the more conservative wording. A final report with zero findings is valid.

## Deliver

Use angular-review's delivery format, adding:

- one money-state summary covering retry/idempotency/unknown-submission behavior;
- one cyber-boundary summary covering caller authority, secret scope, outbound network, output/logging, and mutable management authority;
- a separate activation-prerequisites section;
- discovery provenance for each finding: `host`, `counterpart`, or `both`.

Critical/High produce analytical `REQUEST_CHANGES`; Medium/Low do not unless the user sets another policy. The analytical verdict never authorizes a GitHub review action.

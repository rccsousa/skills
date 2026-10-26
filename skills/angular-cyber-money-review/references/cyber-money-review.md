---
name: cyber-money-review
description: Review a PR, branch, or commit range for concrete money-movement and cyber trust-boundary defects. Use for payment, payout, settlement, ledger, custody, vault, credential, webhook, provider, idempotency, or authorization changes where financial loss or secret exposure is plausible. Do not use for generic code quality review.
---

# Cyber money review

Review one exact target for introduced defects that can move money incorrectly, lose control of money state, widen authority, or expose sensitive data. Nothing is posted, committed, pushed, or changed without explicit authorization.

## Invocation

`/cyber-money-review <PR number|PR URL|branch|base..head|base...head>` or `$cyber-money-review ...`

Honor supplied scope, base, test limits, and output format. If no target is supplied, resolve the PR for the current branch. Never assume the default branch.

## Establish evidence

1. Resolve immutable base/head SHAs and record the reviewed head. Use the PR's declared base. Reuse a clean exact-head worktree or inspect through Git objects; do not disturb user work.
2. Read the title/body, changed files, complete diff, repository requirements, and unchanged callers/consumers needed to trace every changed financial or security contract.
3. Establish the intended caller and audience separately from authentication, authorization, routing, environment gates, and documentation visibility. Inspect generated API, SDK, MCP/tool, or other discovery output when exposure changes.
4. Use primary documentation for provider, vault, cryptographic, protocol, or platform semantics that determine correctness.
5. Run the smallest meaningful focused validation and inspect current CI. Recheck that the head did not move before delivery.

Do not read existing review conclusions before completing the independent pass unless the user asks only to reconcile an already-finished review.

## Money-movement lens

Trace the complete path from authorized intent to irreversible provider/ledger action and through reconciliation, completion, webhook, reversal, and retry consumers.

Verify:

- authority is bound to the actual workspace, owner, account, destination, quote, amount, currency, rail, principal, and operation; caller-supplied identifiers are not treated as authorization;
- destination and beneficiary values cannot be substituted after approval, tokenization, signing, persistence, or quote acceptance;
- amounts use the correct units, precision, sign, currency, fee, FX direction, and rounding at every boundary;
- idempotency keys and client references are stable and bound to the same operation; retries cannot mint a new identity while the prior attempt may exist;
- transaction scope, locks, uniqueness, state transitions, outbox/publication timing, and side effects cannot debit twice, credit twice, publish before commit, or leave an accepted movement unowned;
- response adoption validates ownership, reference, quote, destination, amount, currency, route, and material economics; missing evidence is incomplete, never a match;
- polling, webhooks, recovery, and reversals preserve the same invariants as initial submission;
- mixed-version rollout and intermediate migration states cannot weaken these guarantees.

Classify submission state conservatively:

| State | Required evidence | Allowed action |
| --- | --- | --- |
| Definitely not submitted | Failure before transmission, or an exact provider contract proving rejection before creation | Retry only under the established identity policy |
| May have submitted | Transmission began and the result is timeout, disconnect, redirect, oversized/truncated/non-JSON response, 5xx, unexpected success shape, or unproven 4xx | Lookup/reconcile; never create a new financial identity |
| Accepted and identified | Valid response plus complete owner/reference/destination/economics checks | Adopt and continue lifecycle |
| Terminal | Authoritative provider/ledger evidence under the same checks | Finalize once |

Default to `may have submitted`. A machine code is not proof of pre-submission unless its HTTP status, envelope, operation, and provider contract establish that meaning. A `429` on a money-moving request is uncertain unless the provider contract proves otherwise.

## Cyber lens

Verify:

- authentication identifies the caller and authorization binds that identity to the requested tenant/resource/action; detect confused-deputy paths where a weak caller can drive a stronger key, vault reader, signer, or provider bearer;
- capability-bearing inputs are fixed, allowlisted, or cryptographically bound; inventory who can invoke/update the component before calling a broad capability a defect;
- secrets have the narrowest practical key, container, environment, permission, and rotation scope; include management/update authority, stale resources, rollback copies, logs, errors, tests, and generated artifacts in the blast-radius analysis;
- outbound hosts, schemes, paths, methods, redirects, headers, DNS-sensitive choices, and request sizes are constrained; no caller-controlled SSRF or credential-forwarding path exists;
- untrusted inputs and provider responses are structurally validated without coercion, prototype surprises, header injection, template evaluation, path traversal, or silent defaults;
- returned fields are allowlisted; plaintext destinations, credentials, raw provider bodies, exception text, and sensitive logs cannot escape; redaction cannot be bypassed by nesting or alternate fields;
- timeouts are total, response bodies are bounded, retries are explicit, and failure cleanup cannot leave an unknown financial action treated as absent;
- runtime dependencies, mutable reactor/proxy/function code, provisioning, and patch permissions do not silently enlarge the trusted computing base.

## Findings versus prerequisites

A finding requires an exact `file:line`, reachable supported state, execution path, wrong outcome, practical impact, concise fix, and verification status (`code`, `test`, or `unverified`). Report only defects introduced by the target.

- **Critical/High:** concrete financial loss, duplicate movement, authorization bypass, material secret exposure, or loss of recoverability; blocking.
- **Medium/Low:** concrete but contained incorrectness; non-blocking unless the user defines otherwise.
- **Activation prerequisite:** source is intentionally inactive and safety depends on deployment inventory, key/container scope, routing, or operational verification not represented in the diff.
- **Hardening:** plausible defense with no supported reachable failure. Do not present it as a defect.
- **Load-bearing assumption/evidence gap:** correctness depends on an unverified external or deployment fact.

Do not upgrade a deployment assumption into a code finding. Do not downgrade an implemented unsafe path merely because documentation says operators should avoid it.

## Reconcile another review

When the user supplies another review after the independent pass:

1. Verify every claim against the exact head, contracts, consumers, tests, and primary documentation.
2. Deduplicate by root cause and scenario.
3. Agreement raises attention, not truth; disagreement triggers evidence checking.
4. Explicitly keep, narrow, downgrade, or withdraw each material disagreement. Never manufacture consensus.
5. Produce one converged verdict, retaining activation prerequisites and evidence gaps separately from findings.

## Deliver

Lead with `Verdict: APPROVE | REQUEST_CHANGES`. Then provide findings in Critical/High/Medium/Low order. For each: `file:line`, scenario, wrong outcome, impact, fix, verification.

If clean, say `No actionable findings.` Then report the exact head, focused validation, material activation prerequisites, load-bearing assumptions/evidence gaps, current CI limitations, and whether publication/audience changed. Keep generic observations out of a clean verdict.

Do not draft or post a GitHub review unless the user explicitly asks after seeing the findings.

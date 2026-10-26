---
name: angular-review
description: Run two parallel blind reviews of a PR, branch, or commit range—one by the host and one by the counterpart model—and return independently verified Crit/High/Medium/Low findings plus a draft review. Use only when the user explicitly asks for an angular review or invokes $angular-review. This bundled method covers a single target.
---

# Angular review

Two independent reviews in parallel: the current host and a fresh counterpart model inspect the same exact target without seeing each other's conclusions. After both finish, the host reconciles, deduplicates, and verifies the findings. No council, peer cross-critique, moderator, or user grill. Nothing is posted without user authorization; nothing is committed, pushed, or filed.

## Invocation

`/angular-review <PR#|branch|base..head|base...head>`

This bundled method reviews one PR, branch, or range. A whole-stack review requires a separately installed stack workflow; do not silently review only one member.

Optional user choices override defaults: base ref, reviewer effort, test scope, or output format. Default counterpart effort is high.

## 1. Resolve the exact target

- PR: read current PR metadata, fetch its head and intended base, and record both SHAs.
- Branch/range: resolve immutable base/head SHAs; never assume the default branch is `main`.
- PR already MERGED or CLOSED: review anyway; the first §5 delivery line is `Post-merge review: PR #<n> is MERGED|CLOSED.`
- Reuse a clean exact-head review worktree when available. Otherwise create a detached review worktree under `.worktrees/`. Refuse dirty or ambiguous targets.
- Do not read existing GitHub reviews or comments: they contaminate blindness.
- Relay target, base SHA, head SHA, host, counterpart model, and effort before starting the parallel reviews.

## 2. Gather neutral evidence

Gather one neutral evidence packet before either review. Both reviewers receive the same facts:

- exact PR title/body or target objective;
- base/head SHAs and repository/worktree path;
- changed-file list and full diff, with explicit omissions;
- command/output tails for tests and typechecks;
- unchanged direct-consumer excerpts needed to interpret changed contracts;
- authoritative primary documentation when a finding depends on external semantics.

Do **not** put host findings, suspicions, earlier review output, GitHub comments, proposed defects, or a desired verdict in the shared packet. Neutral test failures are evidence; host interpretations are not.

## 3. Run two blind reviews in parallel

Start both passes from the neutral packet. Do not wait for one review before starting the other when parallel execution is available.

- Host pass: the current Codex or Claude session performs its own complete review. It must write or retain its findings before reading counterpart output.
- Counterpart pass from Codex: invoke a fresh non-persistent `claude -p --model claude-opus-5-5 --effort high` session with read-only tools, or an equivalent isolated Claude Opus facility.
- Counterpart pass from Claude Code: invoke a fresh Codex Sol session through the available isolated model/AoE facility, with read-only tools and no inherited conversation. Use the configured Sol model `gpt-6.1-sol`; do not silently substitute another model. Invoke as:
  `codex exec -s read-only -m gpt-6.1-sol -c model_reasoning_effort=high --skip-git-repo-check - < <prompt-file>`
- Neither reviewer receives the other's findings, analysis, or verdict until both passes are complete.
- Deny file edits, Git/GitHub writes, external messages, and reviewer delegation.
- If either pass fails, report which pass failed. Do not silently substitute another model or describe a single-pass result as angular review.

Use this review contract verbatim in the packet:

> Find only concrete defects introduced by this change. Rank them Critical, High, Medium, or Low. Every finding must identify an exact file/line, reachable inputs and state, wrong outcome, impact, concise fix, and verification status (`code`, `test`, or `unverified`). Report a finding only when the scenario contradicts repository behavior, an explicit requirement, an ADR, or an authoritative external contract. An intentional documented policy choice is not a defect merely because another policy is possible; record it as a load-bearing assumption or evidence gap unless its supported execution produces a concrete unsafe or incorrect outcome. Verify external-product semantics from primary documentation. Separate fact from inference. Reject style advice, generic hardening, speculative possibilities, pre-existing defects, and findings that rely on unsupported product requirements. Return `REQUEST_CHANGES` only for at least one Critical or High finding.

Add these instructions to both passes, outside the contract:

- When the change alters a contract — drops or nulls a persisted field, changes a status code, narrows or renames a returned shape — enumerate every downstream consumer before judging impact. Search by symbol and by field/column name without truncation (`head -N`) or exclusion filters, and open the consumers that read it. State whether the enumeration is complete, or which paths were not covered.
- A backend-intentional change is not cleared until its callers are traced. "Unreachable branch", "dead code", or the PR body's stated intent do not settle impact when a caller observes the behaviour change.
- **Endpoint publication.** When the change adds an HTTP operation or changes where one is published (generated OpenAPI/API reference, SDKs, MCP/tool discovery), establish its intended audience from the PR body, linked requirements, or existing contracts, and inspect the generated publication output, not only decorators. Treat this as an explicit requirement: an operation is not published before its audience is established. Authentication, authorization, environment gates, and gateway routing do not establish audience, and neither does a precedent elsewhere in the codebase. If the audience is unstated, or contradicts where the operation is published, report a High finding framed as a blocking question, verified against the generated output.

- **Provider capability gaps.** A provider operation composed from other calls (probe/throwaway calls, loops or search over a provider client, off-intent endpoint use, undocumented behaviour relied on) without the repository owner's dated approval in the plan or ADR is a Critical finding: it should never have reached a PR. Verify against the provider's primary docs.
Require each pass to return structured output containing: verdict; ranked findings; load-bearing assumptions; evidence gaps; and tests. The draft PR review is written only after reconciliation.

## 4. Reconcile and verify

Only after both passes finish, compare their outputs:

- deduplicate findings by root cause and failure scenario, not wording;
- record which pass found each issue and any material disagreement;
- agreement raises attention, not truth; disagreement triggers evidence checking, not majority vote;
- do not let one pass retroactively invent support for the other.

For every proposed finding from either pass:

1. Reproduce or trace the exact scenario against the diff and unchanged consumers.
2. Check the PR body, linked local requirements, ADRs, and tests for intentional behavior.
3. For external semantics, verify against primary docs; if unavailable, mark unverified and do not promote the claim to Critical/High.
4. Drop findings that only identify a design choice, lack a reachable supported scenario, or contradict documented intent without showing an unsafe/incorrect result.
   An endpoint-publication finding from §3 is not a design choice: keep it unless the PR body, a linked requirement, or an existing contract establishes the audience and the published surface matches it.

Drop any finding that fails verification, even if both reviewers reported it. Do not invent replacement findings. The final report may contain zero findings.

For a reachable concurrency finding, use [deterministic race checks](race-checks.md) and its callable `../scripts/race_check.mjs` harness when controlling the interleaving would verify the claim. Keep each blind pass's hypothesis and adapter private until reconciliation. The harness orders execution; the reviewer owns the invariant and evidence scope.

## 5. Deliver

Return:

- `Verdict: APPROVE | REQUEST_CHANGES`;
- counts for Critical / High / Medium / Low;
- one compact entry per finding: severity, `file:line`, scenario, impact, fix, verification, and `found by host | counterpart | both`;
- material disagreement and why the final report kept, changed, or dropped the claim;
- load-bearing assumptions and material evidence gaps;
- `Enumeration: complete | partial: <paths not covered>`, for the consumer enumeration in §3;
- validation commands/results;
- a concise draft PR review body.

Critical/High warrant an analytical `REQUEST_CHANGES` verdict. Medium/Low do not unless the user defines another policy. This verdict does not determine the GitHub review action. When the user authorizes posting, submit a non-blocking `COMMENT` review by default, including for Critical/High findings. Use GitHub `REQUEST_CHANGES` or `APPROVE` only when the user explicitly requests that action. An autopost instruction authorizes posting without a separate approval step; otherwise show the draft and obtain approval before posting.

## Rules

- Exactly two first passes: host plus counterpart (Opus from Codex; Sol from Claude). No council, moderator, peer discussion, or grill.
- Blind means no host, counterpart, or prior-review conclusions cross the boundary until both passes finish.
- No GitHub posts or replies without user authorization; no commits, pushes, issues, or destructive Git operations.
- Preserve dirty user work. Review artifacts belong outside tracked project files.

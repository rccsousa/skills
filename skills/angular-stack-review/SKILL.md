---
name: angular-stack-review
description: Review an entire PR stack as one coherent change with two parallel blind passes by the host and counterpart model, then verify cross-PR defects, intermediate-state safety, and fix ownership. Use for angular review gh stack followed by a stack number, an angular stack review, or reviewing stacked PRs together. Use for whole-stack reviews rather than isolated PR reviews.
---

# Angular stack review

Apply the two-pass blind method to the entire stack. This skill contains the complete stack workflow and needs no sibling skills. Each reviewer reviews the whole change; do not run separate angular reviews per PR or split PRs between reviewers. Reconcile once, deduplicate across the stack, and assign each verified issue to its appropriate fix location. Nothing is posted without user authorization; nothing is committed, pushed, or filed.

## Invocation

Preferred: `angular review gh stack 1001` or `$angular-stack-review gh stack 1001`.

Also accept `/angular-stack-review <tip-PR#|PR-URL|ordered-PR-list|base..tip|base...tip>`.

`gh stack <number>` explicitly identifies a GitHub stack in the current repository; it is skill input, not a literal shell command. Resolve that stack's full membership and order, including members above any individual PR. Never reinterpret an explicit stack number as a PR number. Accept an explicit repository override when supplied.

Optional choices override defaults: stack boundary, base ref, merge/deploy model, counterpart effort, test scope, or output format. Default counterpart effort is high. A tip PR means discover its ancestor PRs through their base relationships; do not silently include descendants or unrelated sibling branches. A range without PR metadata supports a combined review, with PR attribution explicitly unavailable.

## 1. Freeze the stack

- For a GitHub stack number, resolve the repository and retrieve authoritative stack identity, membership, and order before inspecting individual PRs. Inspect installed `gh stack` help and, when needed, its implementation or primary documentation to find supported read-only retrieval. `gh stack view --json` describes the current local stack, so verify its repository and stack identity before using it for the requested number. Prefer read-only GitHub API retrieval for another stack. Do not run `gh stack checkout`, `sync`, or `link` just to discover membership: checkout changes local state and can fall back from a missing stack number to a PR number. If exact stack resolution is unavailable, report that limitation and request a stack URL or explicit PR list; never silently review PR #1001 instead of stack 1001.
- Read current PR titles/bodies, head/base refs and repositories, SHAs, and open/merged/closed state. Fetch intended bases and heads; never assume `main`. Do not read existing reviews, review summaries, or comments.
- Any member already MERGED or CLOSED: review anyway; the first §5 delivery line is `Post-merge review: PR #<n>[, #<n>…] MERGED|CLOSED.`
- Discover dependencies from PR base relationships, explicit dependency declarations, and Git ancestry. Titles, numbering, and branch naming are hints, not proof. Check an explicit PR list against these relationships instead of trusting its order.
- Record a manifest: repository; stack number/URL when supplied; ordered PRs/dependencies; exact head and base SHAs; each PR's merge-base SHA; root target branch SHA; root review boundary SHA; final tip SHA; merge/deploy assumptions. Explain the distinction between the current root target and the review boundary when they differ.
- For an ordinary linear stack, use the root PR's merge base with its intended target as the review boundary, and verify every included ancestor head is an ancestor of the tip. Review the endpoint diff from that boundary to the tip; do not let range punctuation obscure the actual SHAs. Record current-target drift separately.
- Verify every intended PR contribution is represented at the tip. Stale/rebased parents, already squash-merged ancestors, retargeted PRs, and declared but unmerged dependencies require content/history evidence; ancestry failure alone does not establish a defect or inclusion. Already-landed changes belong to baseline context, not new findings.
- If dependencies are missing, the requested boundary is ambiguous, or branches do not form a coherent integrated tip, explain the exact gap and request only the missing scope decision. Never invent a combined tree, silently omit a dependency, or approve an unreviewed integration. Independent local inspection may continue while scope is unresolved.
- Reuse a clean review worktree at the exact tip, or create a detached review worktree under `.worktrees/`, ensuring it is locally Git-ignored. Preserve dirty or active worktrees; create a separate clean checkout when possible. Review artifacts belong outside tracked project files. Use additional detached snapshots only where boundary verification needs them.
- Relay the ordered stack, immutable boundary/tip, host, counterpart model, and effort before starting reviews.

The reviewed object is the frozen manifest. Recheck remote PR heads, bases, and membership before delivery. If they moved, report which snapshot was reviewed and that the verdict does not cover the new state; do not silently mix versions.

## 2. Gather one neutral packet

Both reviewers receive the same facts before either begins:

- Manifest and exact PR titles/bodies or range objective; documented requirements and merge/deploy guarantees.
- Full boundary-to-tip diff and changed-file list: the primary review surface.
- Each PR's incremental diff and changed-file list, with the exact comparison SHAs. In an unchanged linear chain this is the previous head to the next head. Otherwise explain divergence and use the verified PR merge base; identify inherited or overlapping changes so they are not counted twice.
- A map from changed contracts/files to contributing PRs, plus unchanged direct consumers, callers, configuration, and tests needed to understand them.
- Commands, snapshot SHAs, and output tails for relevant tests/typechecks; distinguish baseline/environment failures from regressions. Follow repository setup and use isolated local test resources.
- Primary documentation for external semantics, where required.
- Explicit omissions, unavailable dependencies, and untested states. Large diffs may be supplied as indexed files accessible to both reviewers; truncation must never masquerade as full coverage.

Keep findings, suspicions, proposed defects, desired verdicts, and prior review conclusions out of this packet. Neutral failures are evidence; host interpretations are not.

## 3. Run exactly two blind whole-stack passes

- Start the host and fresh counterpart from the packet in parallel when available. The host retains its complete findings before reading counterpart output.
- From Codex: use a fresh non-persistent `claude -p --model claude-opus-5-5 --effort high` session with read-only tools, or an equivalent isolated Claude Opus facility.
- From Claude Code: use a fresh isolated Codex `gpt-6.1-sol` session at high reasoning effort, with read-only tools and no inherited conversation. For example: `codex exec -s read-only -m gpt-6.1-sol -c model_reasoning_effort=high --skip-git-repo-check - < <prompt-file>`. Do not silently substitute another model.
- Deny source edits, Git/GitHub writes, external messages, and reviewer delegation. No council, moderator, peer discussion, or grill. Neither pass sees the other's analysis or verdict until both finish.
- Report a failed or unavailable pass explicitly. Never substitute models silently or call one completed pass a completed angular stack review.

Use this inherited review contract verbatim in the packet:

> Find only concrete defects introduced by this change. Rank them Critical, High, Medium, or Low. Every finding must identify an exact file/line, reachable inputs and state, wrong outcome, impact, concise fix, and verification status (`code`, `test`, or `unverified`). Report a finding only when the scenario contradicts repository behavior, an explicit requirement, an ADR, or an authoritative external contract. An intentional documented policy choice is not a defect merely because another policy is possible; record it as a load-bearing assumption or evidence gap unless its supported execution produces a concrete unsafe or incorrect outcome. Verify external-product semantics from primary documentation. Separate fact from inference. Reject style advice, generic hardening, speculative possibilities, pre-existing defects, and findings that rely on unsupported product requirements. Return `REQUEST_CHANGES` only for at least one Critical or High finding.

Add these stack-specific instructions to both passes:

- Review final behavior first: follow complete flows across PR boundaries, including changed interfaces and their consumers, authorization, persistence/migrations, jobs, configuration, and tests where relevant. Detect interactions that isolated PR diffs hide.
- When any PR alters a contract — drops or nulls a persisted field, changes a status code, narrows or renames a returned shape — enumerate every downstream consumer across the whole stack before judging impact, not only within the introducing PR. Search by symbol and by field/column name without truncation (`head -N`) or exclusion filters, and open the consumers that read it. State whether the enumeration is complete, or which paths were not covered.
- A backend-intentional change is not cleared until its callers are traced. "Unreachable branch", "dead code", or a PR body's stated intent do not settle impact when a caller observes the behaviour change.
- **Endpoint publication.** When any PR in the stack adds an HTTP operation or changes where one is published (generated OpenAPI/API reference, SDKs, MCP/tool discovery), establish its intended audience from the PR body, linked requirements, or existing contracts, and inspect the generated publication output, not only decorators. Treat this as an explicit requirement: an operation is not published before its audience is established. Authentication, authorization, environment gates, and gateway routing do not establish audience, and neither does a precedent elsewhere in the codebase. If the audience is unstated, or contradicts where the operation is published, report a High finding framed as a blocking question, verified against the generated output.
- Also inspect changes canceled or superseded at the tip when they can affect an exposed intermediate state or leave durable effects. A clean net diff alone cannot establish safe migration or rollout behavior.
- Review intermediate prefixes and mixed-version states only against the supported merge/deploy model. Distinguish sequential merges with deployment after each PR from deployment gated until the entire stack lands. Merge order does not itself prove deploy order or atomicity. If the model is unknown, report that assumption/gap; do not invent an independent-deployability requirement.
- A gap in an early PR repaired later is not a final-tip finding. Report it only with evidence of a reachable broken intermediate state, required failing merge gate, or lasting side effect. Cite that snapshot and the later repair. Conversely, a final-tip repair does not erase a migration/data effect that survives it.
- Separate final-tip defects, supported intermediate-state defects, and concrete integration failures against the current target. Do not label target drift or an untested merge as a defect without evidence.
- Attribute by root cause and scenario: identify introducing PR(s), affected PRs, and recommended fix PR. Do not blame the last PR merely because the issue is visible there. If attribution is uncertain, say so without weakening a verified stack-level defect.

Each pass returns structured output: verdict; ranked findings with snapshot SHA, `file:line`, scenario, outcome/impact, fix, verification status, scope (final/intermediate/integration), introducing and fix PRs; load-bearing assumptions; evidence gaps; and validation commands/results. Draft the review only after reconciliation.

## 4. Reconcile and verify once

- Deduplicate by root cause and failure scenario across both passes and all PRs. One cross-PR defect gets one finding; list its affected PRs rather than repeating it.
- Record discovery provenance (`host`, `counterpart`, or `both`) and material disagreements. Agreement raises attention, not truth; resolve disagreements with evidence.
- Trace or reproduce every candidate against its exact snapshot, the combined diff, relevant incremental diffs, and unchanged consumers. Check PR intent, requirements, ADRs, and tests. Confirm it is introduced within the reviewed stack rather than inherited from the baseline.
- For intermediate findings, verify exposure/order and any surviving effects. For final findings, check that a later PR has not already repaired the scenario. Verify attribution separately from defect validity.
- Verify external semantics against primary documentation. If unavailable, retain a material evidence gap; do not promote an unverified claim to Critical/High. Drop unsupported defects, policy preferences, and candidates that fail verification even if both passes agree. Zero findings is valid. An endpoint-publication finding from §3 is not a design choice: keep it unless the PR body, a linked requirement, or an existing contract establishes the audience and the published surface matches it.
- Run focused validation at the tip and any implicated intermediate snapshots. Report what ran at each SHA, what failed, and what could not be tested; do not imply every prefix was tested. Avoid rerunning the same checks independently for every PR without a concrete reason.

## 5. Deliver one stack report

- `Verdict: APPROVE | REQUEST_CHANGES`, scoped to the frozen stack; Critical/High/Medium/Low counts. Critical/High warrant an analytical `REQUEST_CHANGES` verdict; Medium/Low do not unless the user specifies another policy. The verdict does not determine the GitHub review action.
- Ordered manifest summary with exact review boundary/tip and material merge/deploy assumptions.
- One compact entry per verified finding: severity, snapshot and `file:line`, final/intermediate/integration scope, scenario, impact, fix, introducing/affected/fix PRs, verification, and discovery provenance.
- Material disagreements and why claims were kept, changed, or dropped; load-bearing assumptions and evidence gaps; validation commands/results with snapshot coverage.
- `Enumeration: complete | partial: <paths not covered>`, for the consumer enumeration in §3.
- Compact PR action map: where fixes belong and which dependent PRs are blocked. This is attribution, not separate independent approval verdicts.
- One concise draft stack review body. Default placement is the tip PR with links to relevant PRs; prepare individual PR comments only if requested.

If either pass or coherent stack coverage is incomplete, report `Review status: INCOMPLETE` and any verified findings; withhold `APPROVE`. Clearly distinguish a frozen-snapshot verdict from approval of remote heads that have changed. When the user authorizes posting, submit non-blocking GitHub `COMMENT` reviews by default, including for Critical/High findings and for each PR when per-PR autopost is requested. Use GitHub `REQUEST_CHANGES` or `APPROVE` only when the user explicitly requests that action. An autopost instruction authorizes posting without a separate approval step; otherwise show the draft and obtain approval before posting. No commits, pushes, issues, or destructive Git operations.

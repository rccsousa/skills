---
name: surgical-review
description: Perform a focused, single-pass review of a small or localized PR for concrete regressions, without the counterpart-model overhead of angular review. Use when the user invokes $surgical-review, asks for a surgical review, or explicitly chooses a lightweight review because angular review is unavailable or disproportionate.
---

# Surgical review

Review one exact PR head deeply enough to catch concrete defects while keeping scope proportional to the change. This is a single-host review: do not invoke Opus, Sol, a council, or review subagents. Do not describe it as an angular review.

Nothing is posted, committed, pushed, or changed. Do not read existing GitHub reviews or comments before reaching the verdict; they bias the pass.

## Invocation

`$surgical-review <PR number|PR URL|branch|base..head|base...head>`

Honor user-supplied base refs, test limits, and output format. If no target is supplied, resolve the PR for the current branch. Never assume the default branch is `main`.

## Review

1. Resolve current metadata and immutable base/head SHAs. For a PR, use its declared base and fetch both refs. Record the reviewed head SHA.
2. Use a clean worktree already at the exact head when available. Otherwise inspect through Git objects or create a detached review worktree under `.worktrees/`. Do not modify the branch or disturb user work.
3. Read the PR title/body, changed-file list, complete diff, and the unchanged code needed to understand every changed contract and execution path. Search direct callers/consumers when behavior, persisted data, API shape, status, gating, or configuration changes.
4. Find only defects introduced by the target. A finding needs:
   - exact `file:line`;
   - reachable input/state and execution path;
   - wrong outcome and practical impact;
   - a concise fix;
   - verification status: `code`, `test`, or `unverified`.
5. Reject style advice, generic hardening, speculative risks, pre-existing defects, and disagreement with an intentional documented policy. Check repository requirements, tests, and authoritative external documentation when they determine correctness.
6. Run the smallest meaningful validation for the changed behavior. Prefer focused tests plus existing CI results. Respect repository setup and secret-handling rules. Never read env files; if the normal test runner loads them, use a safe isolated configuration or report the tests as unrun. Environment-gated or unavailable integration suites are unverified, not passed.
7. Check current CI status and confirm the PR head has not moved before delivering. If it moved, review the new head or state that the verdict applies only to the recorded SHA.

For a reachable concurrency finding, use [deterministic race checks](references/race-checks.md) and the callable harness linked there. Force the relevant stale-read ordering, choose assertions from the repository contract, and distinguish real persistence from repository doubles. This is conditional verification, not a mandatory concurrency suite for every PR.

## Deliver

Lead with findings in severity order: Critical, High, Medium, Low. Keep each finding compact but include all required evidence. Critical/High are blocking; Medium/Low are non-blocking unless the user set another policy.

If there are no findings, say `No actionable findings.` Then report:

- reviewed PR/target and exact head SHA;
- focused validation and result;
- material unverified areas or operational prerequisites;
- whether pending/failing CI limits confidence.

Do not pad a clean review with observations. Do not draft or post a GitHub review unless the user explicitly asks after seeing the findings.

---
name: drive-to-mergeable
description: Drive an open (or about-to-open) PR to a merge-ready state via a dual-source review cascade — dispatch a reviewer subagent + an external PR bot (Copilot/CodeRabbit), triage every finding into fix-now / file-issue / wontfix, autofix the in-scope ones with a regression test, file issues for the rest, resolve threads, and stop at the human merge gate. Use when the user says "/drive-to-mergeable", "review and drive to merge-ready", "take this PR to mergeable", or after a fix branch is ready to ship. Never merges.
disable-model-invocation: true
---

# drive-to-mergeable

Take a focused change from "branch done" to "mergeable, waiting on the human" by running the full external-review loop. This is the **post-PR** counterpart to `/one-shot` (which drives the pre-push plan→implement→review→fix loop): it assumes the code exists and orchestrates getting it reviewed by two independent sources, fixed surgically, and gated.

**Core principle:** Two independent reviewers (a traced subagent + an external bot) catch more than one. Every finding gets a *decision* — fix it here, file it for later, or refute it with reasoning — and nothing ships without that triage on the record.

This skill is **thin glue**. It composes existing skills and only owns the connective tissue + three behaviors nothing else does: (1) request + poll an external bot, (2) fan both review sources into one triage, (3) split findings into **in-scope-fix vs out-of-scope-issue**.

## When to invoke

- A fix/feature branch is implemented and you want it reviewed → merge-ready in one pass.
- `/drive-to-mergeable [PR#]` — PR# optional; defaults to the current branch's PR (or opens one).

Do NOT use for: merging (that's `/merge-pr`) or pre-push feature orchestration (that's `/one-shot`). Red CI is handled inline in step 5 (read the failing check logs, fix, re-push) — no separate skill.

## The cascade

### 1. Internal review (subagent)
Dispatch `surgical-review` (or `superpowers:requesting-code-review`). The reviewer MUST **trace each finding and self-classify severity** (RED/ORANGE/YELLOW or Critical/Major/Minor) — first-pass severities are unreliable (see `verify-review-findings`). Then apply `receiving-code-review`: verify each finding against actual code before acting.

### 2. Open / locate the PR
If no PR exists, open one via `/create-pr` (concise WWH body, conventional title). Commit/push only with explicit approval — see `references/commit-push-policy.md`.

### 3. External review (bot)
**Default bot: Copilot** — request it as soon as the PR exists, before anything else in this step, every run, no asking. (If a repo's PR bot is CodeRabbit instead, use the CodeRabbit path below.)

Request the external reviewer, then **hand the wait to `/mergeable-loop`** — the moment Copilot is requested, invoke `mergeable-loop` with this PR#. It schedules the 3-min watch cron that polls for the bot review + CI, runs steps 4-6 inline on each real change, and self-deletes on merge-ready. You do not block-poll here; the loop owns the wait. (Overnight wait / closing the terminal → route to `/schedule` instead — session cron won't survive.)

Request + poll is scripted — `scripts/request-and-poll-bot.sh <owner/repo> <n> <copilot|coderabbit> [timeout]`. It POSTs the Copilot request (CodeRabbit auto-reviews, no request), polls `gh pr view --json reviews` until the bot review lands or times out, and emits `{bot, reviews, comments}` JSON. Reason over that output; the loop calls the same script. Triage CodeRabbit's Critical/Major findings through step 4 like any other source.

Apply `superpowers:receiving-code-review` to the bot's comments too.

### 4. Triage gate (the net-new step)
Sort EVERY finding (both sources) into exactly one bucket:

| Bucket | Action |
|---|---|
| **in-scope fix** | the bug lives in *this* diff / this PR's surface → fix here (step 5) |
| **out-of-scope / pre-existing** | real, but predates the branch or belongs to another concern → `gh issue create` with file:line + repro, reply on the thread deferring to the issue. **Do NOT expand the PR** — keep it focused. |
| **wontfix** | reviewer is wrong → reply with the code/test that refutes it |

Normalize CodeRabbit severities with the shared classifier — `echo "$body" | scripts/classify-coderabbit-severity.sh` → `{severity, marker}` — instead of eyeballing badges; a critical/major routes to in-scope-fix, nit/refactor defaults to file-issue or wontfix.

The in/out split is the whole point: a widened-scope fix that drags in a pre-existing race (TOCTOU, etc.) is exactly the scope-creep failure mode this triage exists to prevent. Default a pre-existing finding to **file-issue**, not patch-on-top.

### 5. Autofix in-scope
For each in-scope finding: fix + add a **regression test** that fails before / passes after. Then verify — see guardrails. Commit (conventional, no co-author) on approval; push.

### 6. Resolve + gate
- Reply on threads first, then **resolve** them with `scripts/resolve-pr-threads.sh <owner/repo> <n>` (fetches unresolved threads via the `reviewThreads` GraphQL connection, fires `resolveReviewThread` per thread; `--dry-run` to preview). Works the same for Copilot and CodeRabbit.
- Run `pr-ready` for the mergeability report.
- **Stop.** Ping the human for final manual review. Never `gh pr merge` (route through `/merge-pr`).

## Guardrails (hard-won)

- **Scoped format only.** `mix format` / prettier with NO path arg reformats the whole repo and silently balloons the diff. Always pass explicit changed-file paths, or revert the spillover before committing.
- **Baseline before blame.** Before attributing a test failure to your diff, run the same test on `origin/<base>`. Pre-existing failures (external deps, fixture gaps) are not yours — note them, don't chase them.
- **Verify, don't assert.** Run the tests + format check and read the output before claiming green (`verification-before-completion`).

## Composes

`surgical-review` · `superpowers:receiving-code-review` · `pr-ready` · `verify-review-findings`. Chains after `/one-shot`; hands off to `/merge-pr`.

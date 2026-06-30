---
name: feature-flow
license: MIT
description: Orchestrate a feature end-to-end through plan → implement → review → fix. Final merge is performed manually by the user on GitHub. Use when the user says "take this through to merge-ready", "ship this autonomously", "full flow", "run the pipeline", or after approving a plan and asks for autonomous execution. Scales the pipeline to feature complexity.
disable-model-invocation: true
---

# Feature Flow

End-to-end orchestration for shipping a feature. Each phase dispatches the right specialised agent, verifies the artefact, and feeds the next phase.

## Phases (full pipeline)

```
plan → (issues/PRD if multi-PR) → implement → review → fix
```

1. **Plan** — already exists or just produced via `grill-me` / `brainstorming` + `writing-plans`. The plan file path is the input to the next phase.
2. **PRD / issues** (only if multi-PR scope) — split into independently-grabbable issues via `to-issues` or publish a PRD via `to-prd`. Skip when the plan fits in a single ~1k LOC PR.
3. **Implement** — dispatch a sonnet-4-6 worker agent (worktree-isolated) to execute the plan task-by-task following `subagent-driven-development` / TDD. **Output: local commits on a feature branch, tests green. NO push, NO PR.** Orchestrator pauses and waits for the user to push + open the PR themselves (no auto-push, no auto-PR). The user resumes the pipeline by handing back the PR number.
4. **Review** — dispatch `superpowers:code-reviewer` against the PR. Default to local draft review unless user has standing approval; user CLAUDE.md may override.
5. **Fix** — dispatch a worker via `receiving-code-review` to triage the review (red/yellow only), apply fixes, push, resolve threads.

**Merge is done manually by the user on GitHub** — the skill stops after fix. Do not invoke `gh pr merge` and do not delete the plan file automatically; surface a "ready to merge" summary for the user (CI status, threads resolved, plan path) and leave the rest to them.


## Complexity gating

Pick the lightest pipeline that fits.

| Signal                                     | Pipeline                     |
| ------------------------------------------ | ---------------------------- |
| Trivial edit (typo, rename, single-line)   | Skip pipeline. Fix inline.    |
| Single localised feature, fits in one PR   | implement → review → fix (user merges) |
| Multi-PR feature                           | Split via `to-issues` first, then run full pipeline per slice (user merges each) |
| Cross-system / phase-level epic            | PRD via `to-prd`, then per-issue full pipeline (user merges each) |

If unsure, ask the user once. Don't ask between every phase — the user invoked this skill to avoid micro-approvals.

## Dispatch rules

- **Default model: sonnet-4-6** for all worker agents (per global CLAUDE.md). Escalate to opus only on `needs-opus`-tagged steps in the plan.
- **Isolation:** use `isolation: "worktree"` for the implementation phase so the worker gets a clean branch + can push without colliding with the parent session's working tree.
- **Sequential, not parallel:** each phase consumes the prior phase's output (PR number, review URL, etc.). Don't fan out.
- **Foreground:** run agents in the foreground when their output is needed for the next dispatch (PR number from implement → review). Background is acceptable only for the final merge if the user wants to disengage.

## Commit & push modes per phase

See `references/commit-push-policy.md` for the full policy. This skill's per-phase modes:

| Phase | Mode | Behavior |
|---|---|---|
| implement | **strict-stop** | local commits OK; HARD STOP on `git push` and `gh pr create`. User opens PR. |
| review | n/a | read-only |
| fix | **lax** | autonomous-flow invocation = pre-authorized to push fixes |

Merge is performed manually by the user on GitHub; the skill never runs `gh pr merge`.

## Artefact handoff

Each phase must return a small, structured payload:

- **Plan phase →** absolute path to plan file.
- **Implement →** branch name + commit SHAs + local test status + "what was done / what was deferred" note. (No PR yet — user pushes + opens PR, then hands back the PR number.)
- **Review →** review URL + counts (red/yellow/nit).
- **Fix →** commit SHA(s) + thread-resolution count + a "ready-to-merge" summary for the user (CI status, threads resolved, plan file path) so they can perform the merge on GitHub.

Pass these forward verbatim to the next agent's prompt so it has zero ramp-up.

## Halt conditions

Stop the pipeline and return to the user when:

- Implementation agent reports a blocker it can't resolve (failing test it can't fix, ambiguous spec, missing fixture/secret).
- Review surfaces a red comment that requires architectural rethink (not a local fix).
- CI is red after the fix phase and the cause isn't obviously addressable in this PR.
- Merge target has diverged and `catch-up-main` is needed — invoke that skill and surface the result; the user still performs the merge.

In all halt cases, summarise state + ask the user how to proceed. Don't silently retry.

## Worker prompt skeletons

Each worker prompt should brief the agent like a cold colleague. Always include:

1. The phase name + the artefact path (plan / PR / review URL).
2. The relevant CLAUDE.md / memory rules they must respect (PR size, commit conventions, no-co-author, scope of fixes).
3. The expected return payload shape.
4. "Sonnet-4-6 unless plan tags `needs-opus`" reminder.

### Implement-phase prompt skeleton

```
You are the implementation worker for <feature-name>. Plan: <absolute-path>.

Read the plan in full, then execute task-by-task using the superpowers:subagent-driven-development discipline (red → green → commit per step). Sonnet-4-6 is your default; only escalate steps explicitly tagged `needs-opus`.

Constraints:
- Project CLAUDE.md (~/projects/<repo>/CLAUDE.md) and global rules apply.
- Keep the diff under ~1k LOC. If scope balloons, stop and report.
- Conventional Commits, no Claude co-author.
- **HARD STOP after local commits.** Do NOT `git push`. Do NOT `gh pr create`. The user pushes and opens the PR themselves.
- Verify tests + format + lint are green locally before reporting done.
- Defer manual smoke-testing steps to the user; list them in your return payload (they'll go in the PR body).

Return: branch name, commit SHAs, local test/lint status, deferred-tasks summary.
```

### Review-phase prompt skeleton

```
Review PR #<number> against the plan at <plan-path>. Focus on red (bug/security/regression) and yellow (correctness/clarity) findings; record nits but don't block on them.

Constraints:
- Don't post to GitHub unless explicitly authorised — local draft review by default.
- Compare implementation against the plan; flag missing tasks.
- Verify CI status via `gh pr checks` before recommending merge.

Return: structured findings (red / yellow / nit), CI status, merge recommendation.
```

### Fix-phase prompt skeleton

```
Address review findings on PR #<number>. Review findings: <inline> (red + yellow only).

Constraints:
- Skip nits unless they're cheap.
- One commit per logical fix; push to the same branch.
- Reply on each thread + mark resolved on GitHub.
- Don't expand scope. Out-of-scope findings → file follow-up issues, don't fix here.

Return: commit SHAs, threads resolved, deferred follow-ups.
```

### Ready-to-merge summary (no merge phase)

After the fix phase, surface a single concise summary for the user — they merge on GitHub themselves. Include:

- PR number + URL
- `gh pr checks <number>` status (green/red/pending)
- Threads resolved count
- Plan file path (so they can delete it post-merge)
- One-line "merge when ready" prompt

Do NOT call `gh pr merge`. Do NOT delete the plan file. Do NOT delete the branch.

## Why this skill exists

The user wants a one-shot "ship this" command after the design is settled. Without this skill, each phase needs a fresh prompt and full re-briefing. With it, the orchestrator hands artefacts forward and the user only intervenes on halts.

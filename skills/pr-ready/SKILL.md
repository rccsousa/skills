---
name: pr-ready
description: Verify a PR is in a mergeable state (CI green, no unresolved threads, conventional commits, not draft). Reports state — does NOT merge. Use /merge-pr to actually merge. Triggers - "/pr-ready", "is this ready?", "is this mergeable?", or after any agent claims work is "done"/"ready"/"good to go".
---

# pr-ready

Two-step: produce the mergeability report, then verify with live commands. No claim ships without evidence. **This skill never runs `gh pr merge`** — use `/merge-pr` for the action.

## Triggers

- `/pr-ready` or `/pr-ready <PR#>`
- After feature-flow, address-bot-review, surgical-review, or any agent says "ready to merge"
- User asks "is this ready?" / "is this mergeable?"
- Right after CI run reports back

## Steps

1. **Resolve PR**
   - Arg given → that number
   - Else → current branch (`gh pr view --json number`)
   - No PR → STOP, suggest `gh pr create`

2. **Generate summary**
   - Title, base, +adds/-dels, commit count, issue tracker ID
   - One-line "what shipped" (from PR body or commit titles)

3. **Verify** — `bash ~/.claude/lib/pr-checks.sh <n>` → JSON report
   - Parse: each of `{ci, merge, review, size, commits, draft}` has `.ok` boolean
   - On `review.unresolved_threads > 0` → fetch thread detail:
     ```bash
     ~/.claude/lib/fetch-review-threads.sh <n>   # → .threads[] {path, line, isResolved, comments}
     ```
     Filter to `isResolved == false` for the unresolved list.
   - Script reads `origin/<base>`; if base not fetched, run `git fetch origin <base>` first

4. **Report (structured)**

   ```
   PR #1234 — feat(my-feature): xyz
   base: main ← feat/my-feature  +312 -45  3 commits

   ✓ CI            all 7 checks pass
   ✓ merge         CLEAN, no conflicts
   ✗ review        1 unresolved thread (file: src/foo.ts L42 — @sara)
   ✓ size          357 LOC < 1k
   ✓ commits       conventional
   ✓ status        not draft

   BLOCKED — resolve thread on src/foo.ts:42
   ```

   On all-green: print `MERGEABLE — run /merge-pr to merge` as the last line. Don't suggest `gh pr merge` directly; route the action through `/merge-pr`.

## Verification contract (hard rules)

Skill MUST NOT print "MERGEABLE" unless `pr-checks.sh` JSON `.ready == true`.
That means ALL of:
- `ci.ok == true` AND `ci.total > 0` (no checks configured = not mergeable)
- `merge.ok == true` (`merge.state == "CLEAN"`)
- `review.ok == true` (`decision == "APPROVED"`, zero unresolved threads). Skip only if repo has no required reviewers.
- `draft.ok == true` (not draft)
- `commits.ok == true` (all conventional)

Any failure → print failing rule + JSON snippet + stop. Yellow ≠ green. Pending ≠ pass.

## Out of scope

- Performing the merge (`gh pr merge`) → `/merge-pr`
- Opening the PR (commit/push/draft) → `/create-pr`

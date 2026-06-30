---
name: address-bot-review
license: MIT
description: Use when asked to fix/address automated review-bot comments on a PR (CodeRabbit, or any bot via --bot). Fetches findings, fixes Critical/Major only (skips nits unless trivial), commits, pushes, replies to each thread, and resolves them on GitHub.
disable-model-invocation: true
---

# address-bot-review — Auto-fix review-bot findings

Triage and fix actionable review-bot comments on a PR. Only Critical and Major
findings are fixed by default. Minor/Nit/Refactor suggestions are skipped
unless the fix is a one-liner.

Works with any automated reviewer. **CodeRabbit** is the reference bot (default);
pass `--bot generic` for plain-English severity labels from other bots or human
reviewers. The severity vocabulary lives in `lib/classify-review-severity.sh`.

## Arguments

- `$1` — PR number (required). Repo is auto-detected from `git remote get-url origin`.
- `--bot <coderabbit|generic>` — which marker vocabulary to classify with (default: `coderabbit`).
- `--bot-login <login>` — the bot's GitHub author login to filter on (default: `coderabbitai[bot]`).

If no number is provided, ask for one.

## Process

### 1. Fetch PR + review data (parallel)

```bash
gh pr view <num> --json headRefName,baseRefName,headRepositoryOwner,state,url
scripts/fetch-review-threads.sh <num>   # reviews + threads (id, databaseId, isResolved, isOutdated, path, line)
```

The fetcher returns ALL threads. Only consider comments authored by the target
bot login (default `coderabbitai[bot]`, also `coderabbit[bot]`; override with
`--bot-login`). Ignore threads where `isResolved` is true or `isOutdated` is
true. Use `thread.id` to resolve and `comment.databaseId` to reply (step 7).

### 2. Classify severity

Pipe each thread's first comment body through the shared classifier — it
emits the raw severity token (single source of marker truth):

```bash
echo "$body" | scripts/classify-review-severity.sh --bot <coderabbit|generic>
# → {"severity":"critical|major|minor|nit|refactor|verification|unknown", "marker":"...", "bot":"..."}
```

Map the `severity` token to this skill's action policy:

| `severity`                     | Bucket        | Action                    |
| ------------------------------ | ------------- | ------------------------- |
| `critical` / `major`           | **fix**       | always fix                |
| `minor`                        | **maybe**     | fix only if one-line diff |
| `nit` / `refactor`             | **skip**      | skip unless trivial       |
| `verification`                 | **skip/ack**  | verify mentally, reply    |
| `unknown` (actionable claim)   | **skip**      | skip unless trivial       |

Summarize buckets to the user before touching code: `N critical/major to fix, M nits to skip`.

### 3. Check out the PR branch

Use `git worktree list` to find an existing checkout. If the branch isn't checked out anywhere, run the fixes from the main repo root (`cd "$(git rev-parse --show-toplevel)"` from the upstream clone, not from another worktree). Never switch branches inside an unrelated worktree.

If the PR is from a fork, use `gh pr checkout <num>`.

### 4. Apply fixes

For each finding in the **fix** bucket:

- `Read` the file at the cited lines (don't trust the diff_hunk alone — the file may have moved on).
- Apply the minimum change that resolves the finding. No surrounding cleanup, no drive-by refactors.
- If the finding is wrong (false positive), skip it and note why in the reply.
- If two findings overlap, fix once and reply to both threads.

Do NOT:
- Expand scope beyond the cited lines.
- Fix nits that weren't in the fix bucket, even if you notice them.
- Rewrite unrelated code the reviewer happens to mention in passing.

### 5. Verify

Run the minimum viable check for the files touched, using the repo's own tooling:
- Code: the repo's formatter in check mode + its compile/type check (skip for config/docs).
- YAML / Markdown / config: visual diff only.
- If the repo has a pre-commit hook/alias and the change is non-trivial, run it.

Do not run the full test suite unless the findings touched logic.

### 6. Commit + push

**Mode: lax** (see `references/commit-push-policy.md`). One commit per logical fix (or one squashed commit if all findings are in same file). One-liner message per the policy. Push to PR branch. On non-fast-forward reject → STOP and ask; never force-push.

### 7. Reply + resolve each thread

For each finding you addressed, post a reply and resolve the thread:

```bash
# reply (use the top-level comment id)
gh api repos/<o>/<r>/pulls/<num>/comments/<comment_id>/replies -f body='<reply>'

# resolve (use the GraphQL thread id)
gh api graphql -f query='mutation { resolveReviewThread(input:{threadId:"<thread_id>"}){ thread { isResolved }}}'
```

Reply bodies: one sentence, concrete. "Fixed in <sha> — <what changed>." For false positives: "Skipping — <why>, see <file:line>." Do not thank the bot.

For findings you deliberately skipped (nits, false positives), reply but do NOT resolve — let the human close them.

### 8. Report

Summarize to the user:
- Findings fixed (with file:line)
- Findings skipped (with reason)
- New commit sha(s) and push target
- Link to the PR

## Guardrails

- **Never fix without classifying first.** Show the bucket counts so the user can redirect.
- **Never force-push.** If the branch diverged, surface the conflict and ask.
- **Never commit to `main`.** Confirm `git branch --show-current` matches the PR head ref.
- **Never touch files outside the cited findings.** If you notice an unrelated bug, open an issue (`gh issue create`) and mention it in the report — do not expand the PR.
- **Respect drafts.** If the PR is a draft, ask before pushing.
- **Skip if no bot review exists yet.** Tell the user to wait for the bot.

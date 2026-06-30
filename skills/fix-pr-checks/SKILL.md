---
name: fix-pr-checks
description: Diagnose and fix failing CI checks on a PR (lint/format/type/test). Triggers - "/fix-pr-checks", "checks are failing", "fix the PR checks", "CI is red on <PR#>". Finds the real failure, fixes only files in your diff, verifies locally before pushing.
disable-model-invocation: true
---

Fix red CI on a PR. Bias: find the *real* failure, fix only files in your own
diff, verify locally before pushing.

## 0. Identify the failing check

```bash
gh pr checks <PR#>            # which check is `fail`
gh pr view <PR#> --json headRefName,mergeable,state
```

Pick the `fail` row, open its job log:

```bash
gh run view <run-id> --log-failed | tail -80
```

## 1. Classify the failure

From the log, bucket the failing check:

| Bucket | Typical signal | Auto-fixable? |
|--------|----------------|---------------|
| **format** | "needs formatting", diff-style output | yes — run the formatter |
| **lint** | rule violations | sometimes — autofix flag, else hand-fix |
| **type** | compiler/type-checker errors | hand-fix |
| **test** | failing assertions | hand-fix (run locally first) |
| **other** (generated artifacts, schema drift, etc.) | check-specific | regenerate per repo docs |

## 2. The warnings-vs-errors trap (most common lint false alarm)

Many linters print **both warnings and errors**, but **only errors fail CI**. A
red lint job often sits under 100+ pre-existing, harmless warnings. Do NOT grep
raw linter output and start fixing every hit.

Isolate the actual errors first — use the tool's summary/error-only mode (e.g. a
`--reporter=summary`, `--quiet`, or `--max-warnings=0` style flag, whichever the
repo's linter supports). Read the bottom line: `Found N errors`. Only the **N
errors** matter. Formatting mismatches are frequently reported as errors and are
the usual culprit.

## 3. Fix

- **Format errors** (the common case): run the repo's formatter in write mode on
  ONLY the files flagged as needing formatting.
- **Lint errors**: apply the linter's autofix if it has one; otherwise fix the code.
- **Type/test errors**: fix the code; re-run the specific check locally.

## 4. Scope discipline

Only touch files in YOUR diff:

```bash
git diff --name-only origin/main...HEAD
```

Pre-existing warnings in files you didn't change are **not yours** — leave them
(surface as a follow-up in chat, don't expand the PR). A formatting error in a
file *you* edited (e.g. a stray trailing blank line your edit left) IS yours.

## 5. Confuse-check: branch vs environment

If a violation reproduces on pristine main too, it's not your branch's fault —
verify before blaming your diff:

```bash
git checkout -q origin/main && <run the same check> | tail -3
git checkout -q <your-branch>
```

(Worktree-clean only. Stash first if dirty.) If main shows the same *errors*,
main is genuinely red and it's a wider issue — flag it, don't silently absorb.

## 6. Verify, then hand off for commit

Re-run the failing check locally until clean (want: 0 errors). Show the diff
stat, then **stop for explicit approval before committing/pushing** (no
auto-commit/push). After push, confirm green:

```bash
gh pr checks <PR#>
```

## Other checks (quick pointers)

- **Generated artifacts / schema drift** (OpenAPI, GraphQL, error docs, etc.):
  regenerate using the repo's documented command, commit the regenerated file.
  Don't hand-edit generated output.
- **test**: run the failing suite locally before pushing; never push a "should
  be fixed" guess into CI.

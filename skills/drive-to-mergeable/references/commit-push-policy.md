# Commit & push policy (shared)

Single source of truth for commit/push behavior across skills. Skills declare their mode and inherit everything else.

## Modes

- **strict** (default) — no `git commit`, no `git push`. Prepare diff, surface to user.
- **relaxed** — `git commit` allowed; `git push` only with explicit user greenlight in current turn.
- **lax** — both allowed without per-turn confirm.
- **strict-stop** — implementation may commit locally; HARD STOP on push + `gh pr create`. User opens PR.
- **lax-on-ready** — auto-proceed only when an external gate (e.g. `pr-checks.sh .ready=true`) returns ok; halt otherwise.

## Skill mode index

| Skill / phase | Mode | Why |
|---|---|---|
| `catch-up-main`, `catch-up-pr-base` | lax | mechanical upstream merge; user invokes to unblock |
| `address-coderabbit` | lax | invocation = "land fixes on PR"; commit-only is useless |
| `feature-flow` implement | strict-stop | per `feedback_commit_workflow` — user pushes + opens PR |
| `feature-flow` fix | lax | autonomous-flow invocation = pre-authorized |
| `feature-flow` merge | lax-on-ready | only on `pr-checks.sh .ready=true`; halt otherwise |
| default / unspecified | strict | re-ask per task |

## Message rules (all modes)

- One-liner. No body. No trailers.
- Conventional Commits prefix (`feat:`, `fix:`, `chore:`...) when the repo uses CC. Catch-up merge commits use `--no-edit`.
- Never `Co-Authored-By: Claude`. Never Claude as author.
- Author: the repo's own git identity — pass `--author=` if local git config differs.
- Stage only files relevant to current task. Respect intentionally unstaged files (`feedback_unstaged_changes`).

## Lint + tests before commit (all non-strict modes)

- `bun run lint` must pass.
- Tests: full suite for catch-up flows; targeted for in-PR fixes (`feedback_test_lint_cadence`).
- On fail: stop + surface. Never commit broken state.

## Push rules

- Never `git push --force` / `--force-with-lease` without explicit user approval in current turn.
- On non-fast-forward reject: fetch + merge `origin/<branch>` and retry (catch-up-pr-base pattern). Never auto-force.
- Never push to `main` / `prod`. Confirm `git branch --show-current` != main first.

## Ref-mutating ops (always require explicit user approval, regardless of mode)

- `git rebase` outside catch-up flow
- `git reset --hard`
- `gh pr merge` (except `feature-flow` merge-phase on `.ready=true`)
- `gh pr create` (always — orchestrators never open PRs)

## Authority guard (hooks)

- `~/.claude/hooks/branch-catchup.sh` (SessionStart) auto-merges + pushes only when PR author == `rccsousa`. Preserve gate. Scope via `gh pr list --author '@me'`.

# claude-skills

A curated, sanitized set of [Claude Code](https://claude.com/claude-code) skills
for PR workflow, code review, and repo housekeeping. Drop them into `~/.claude/`
and Claude Code picks them up.

## Install

Each skill is **self-contained** — its helper scripts and policy docs are
vendored inside the skill folder — so you can install one, some, or all of them.

**Per-skill, via the [`skills`](https://github.com/vercel-labs/skills) CLI:**

```bash
npx skills add rccsousa/skills              # pick interactively
npx skills add rccsousa/skills --skill pr-ready
npx skills add rccsousa/skills --all        # every skill
```

**Whole set, via symlink:**

```bash
git clone https://github.com/rccsousa/skills.git
cd skills
./install.sh            # symlinks skills/ into ~/.claude
```

Re-running `install.sh` is safe — it never overwrites existing non-symlink files.

**Dependencies:** `gh` (GitHub CLI), `jq`, `perl`. Optional: a
[context7](https://github.com/upstash/context7) MCP server for the `context7-mcp`
skill.

## Skills

### PR workflow
| Skill | What it does |
|-------|--------------|
| `pr-ready` | Verify a PR is mergeable — CI green, no unresolved threads, conventional commits. |
| `pr-interview` | Before push/merge, quiz the author on the diff to catch shipped-but-unread code. |
| `request-review` | Gate the draft → ready-for-review flip on the review bot being done. |
| `merge-pr` | Merge a reviewed, approved PR. |
| `fix-pr-checks` | Diagnose + fix failing CI (lint/format/type/test), fixing only your own diff. |
| `catch-up-main` | Absorb upstream `main` into a diverged feature branch (merge/rebase decision). |
| `feature-flow` | Orchestrate a feature end-to-end: plan → implement → review → fix. |
| `drive-to-mergeable` | Drive an open PR to merge-ready via a dual-source review cascade (subagent + Copilot/CodeRabbit) — triage every finding into fix-now / file-issue / wontfix, autofix in-scope with a regression test, resolve threads. Stops at the human merge gate; never merges. |
| `mergeable-loop` | The watch engine for `drive-to-mergeable` — a self-pacing 3-min session cron that polls the PR and escalates the autofix cascade on each real change (new bot findings / red CI), self-deleting on merge-ready. |

### Feature pipeline (`one-shot`)
| Skill | What it does |
|-------|--------------|
| `one-shot` | Drive a feature idea → merge-ready: plan → implement → review → fix, with `hitl`/`grill`/`auto` autonomy modes. Stops at "ready to merge". |
| `code-review` | Review a diff (local branch or open PR) → structured findings packet (must-fix / should-fix / consider / nit). Feeds `code-fix`. |
| `code-fix` | Apply fixes from a `code-review` packet — commits, optionally pushes + replies on threads. |
| `create-pr` | Open a PR with a Conventional-Commits title and a What/Why/How body. |
| `create-commit` | Stage + commit with a one-line Conventional-Commits message, grouped by logical change. |

`one-shot`'s `grill` mode and PRD/issue flows call **companion skills**
(`grill-with-docs`, `write-a-prd`, `prd-to-issues`, `issue-worker`) that live in a
separate `building` plugin — not vendored here. Without them, run `--mode=hitl` or
`--mode=auto`; `code-review`/`code-fix`/`create-pr`/`create-commit` and the repo's
`council-of-agents` all resolve from this repo.

### Code review
| Skill | What it does |
|-------|--------------|
| `address-bot-review` | Triage + fix automated review-bot comments (CodeRabbit or any bot). |
| `surgical-review` | Strict code-reviewer subagent — SRP, naming, scope discipline. |
| `review-codex-pr` | Grumpy/nitpicky adversarial review of a PR. |
| `deep-audit` | Audit someone else's branch/PR as an external reviewer (read-only). |
| `verify-review-findings` | Adversarially verify review findings against source + runtime before presenting. |
| `red-team-findings` | Hand verified findings to a fresh independent agent to try to refute them. |
| `council-of-agents` | Parallel multi-lens planning. |

### Feedback → issues
| Skill | What it does |
|-------|--------------|
| `triage` | Turn raw tester/user feedback into curated, agent-pickup GitHub issues, one item at a time. Feedback arrives **pasted** (message + screenshots) or **pulled from a Basecamp inbox column**. Grounds each item in the repo (read-only Explore), reaches a verdict, files a rich `file:line` issue; in Basecamp mode, comments the issue URL back on the card and moves it to a triaged column. |

`triage`'s Basecamp mode needs the `basecamp` CLI (37signals'
[`basecamp/basecamp-cli`](https://github.com/basecamp/basecamp-cli) plugin,
installed separately) and a repo wired via `.basecamp/config.json`. Without it,
`triage` still runs in **pasted**
mode — paste a tester message + screenshots and it files issues into the current
repo. Both modes require `gh`.

### Repo / workflow housekeeping
| Skill | What it does |
|-------|--------------|
| `housekeeping` | Prune stale worktrees, delete plan files for merged PRs, tidy after a task. |
| `sync-worktree-skills` | Symlink project `.claude/skills/` into a fresh `git worktree`. |
| `pending` | Track pending todos across sessions in a checkbox memory file. |
| `dream` | Consolidate / clean up / review memories. |

### Meta (skill authoring)
| Skill | What it does |
|-------|--------------|
| `audit-skills` | Audit skills for visibility flags, deterministic-vs-AI steps, cross-skill dup. |
| `improve-skill` | Review the exchange after a skill ran and propose enhancements. |
| `context7-mcp` | Fetch current library/framework docs via the context7 MCP. |

## Shared scripts (`lib/`)

Deterministic helpers the skills shell out to (kept out of the prompt so the
logic is testable and the marker tables have a single source of truth).

`lib/` is the **canonical source**. `vendor-skills.sh` fans these files out into
each skill that uses them (`skills/<name>/scripts/` for `.sh`, `references/` for
`.md`) so every skill is self-contained for a standalone `npx skills` install.
Edit `lib/` and re-run `vendor-skills.sh` — never hand-edit the vendored copies.

- `classify-review-severity.sh` — pluggable severity classifier for review bots (CodeRabbit reference adapter + `generic` fallback).
- `fetch-review-threads.sh` — single GraphQL fetch of a PR's reviews + threads.
- `pr-checks.sh` — PR mergeability/CI/commit-convention report as JSON.
- `extract-interview-hunks.sh` — per-hunk churn + risk-keyword stats from a diff.
- `get-worktree-info.sh` — normalized `git worktree list` layout.
- `housekeeping-snapshot.sh` — per-worktree cleanup state.
- `catch-up-decide.sh` / `catch-up-shared.md` — merge-vs-rebase decision + flow.
- `commit-push-policy.md` / `review-output-contract.md` — shared policy docs.

## Notes

- **This is a sanitized export.** It's maintained as its own repo, not a
  two-way mirror of a private working dir. Skills here are generalized — your
  fork is the place to re-add org-specific commands, CI checks, or conventions.
- **No external proxy required.** Skills call `git`/`gh`/`jq` directly.
- Most skills set `disable-model-invocation: true` (side-effecting: commit,
  push, merge) so they only run when you explicitly invoke them.

## License

MIT — see [LICENSE](LICENSE).

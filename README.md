# claude-skills

A curated, sanitized set of [Claude Code](https://claude.com/claude-code) skills
for PR workflow, code review, and repo housekeeping. Drop them into `~/.claude/`
and Claude Code picks them up.

## Install

```bash
git clone https://github.com/<you>/claude-skills.git
cd claude-skills
./install.sh            # symlinks skills/ + lib/ into ~/.claude
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

### Repo / workflow housekeeping
| Skill | What it does |
|-------|--------------|
| `housekeeping` | Prune stale worktrees, delete plan files for merged PRs, tidy after a task. |
| `sync-worktree-skills` | Symlink project `.claude/skills/` into a fresh `git worktree`. |
| `find-skills` | Discover which skill fits a task. |
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
logic is testable and the marker tables have a single source of truth):

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

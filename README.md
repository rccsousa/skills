# claude-skills

A small set of [Claude Code](https://claude.com/claude-code) skills for triage,
PR workflow, and autonomous maintainer pipelines. Drop them into `~/.claude/` and
Claude Code picks them up.

## Install

Each skill is **self-contained** — its helper scripts and policy docs are
vendored inside the skill folder — so you can install one, some, or all of them.

**Per-skill, via the [`skills`](https://github.com/vercel-labs/skills) CLI:**

```bash
npx skills add rccsousa/skills                          # pick interactively
npx skills add rccsousa/skills --skill install-maintainer
npx skills add rccsousa/skills --all                    # every skill
```

**Whole set, via symlink:**

```bash
git clone https://github.com/rccsousa/skills.git
cd skills
./install.sh            # symlinks skills/ into ~/.claude
```

Re-running `install.sh` is safe — it never overwrites existing non-symlink files.

**As a plugin marketplace** — this repo is also a Claude Code plugin
marketplace, which is how the GitHub Actions workflows that `install-maintainer`
generates deliver skills to a runner:

```yaml
plugin_marketplaces: https://github.com/rccsousa/skills.git
plugins: rccsousa-skills
```

**Dependencies:** `gh` (GitHub CLI), `jq`. `install-maintainer` additionally
needs `python3`.

## Skills

| Skill | What it does |
|-------|--------------|
| `install-maintainer` | Install an autonomous maintainer pipeline into a repo: intake queue → grounded issue → draft PR → driven-to-mergeable, stopping at a human merge gate. Ships GitHub Actions templates, a pluggable intake-source adapter contract, and the harness that proves the templates still match a working pipeline. |
| `triage` | Turn raw tester/user feedback into curated, agent-pickup GitHub issues, one item at a time — parse, ground it in the repo with `file:line` refs, reach a verdict, file. Feedback arrives pasted or pulled from a queue. |
| `one-shot` | Take an issue from cold start to a draft PR: implement, run the repo's real gates, push, open the PR. Never merges. |
| `drive-to-mergeable` | Drive an open PR to merge-ready via a dual-source review cascade (a review subagent + an external bot) — triage every finding into fix-now / file-issue / wontfix, autofix the in-scope ones with a regression test, resolve threads. Stops at the human merge gate; never merges. |

These four compose: `install-maintainer` wires the other three into three GitHub
Actions stages, so a repo can triage and implement its own queue with a human
gating the queue at one end and the merge at the other.

`nightshift` is the unattended, many-issues form of the same idea — run it and go
to bed:

| Skill | What it does |
|-------|--------------|
| `nightshift-prep` | Get a repo and its backlog ready for a night. Sets up labels, config and the core-path gate, checks the permission ceiling, then scores every open issue for whether an unattended session could actually finish it and nominates the ones you approve. Stops at nomination. |
| `nightshift` | Drain a labelled GitHub issue queue overnight. Enriches each issue, then emits a detached bash driver that runs one headless `one-shot` session per issue in its own worktree, opening a draft PR each. Parks itself on the usage limit, waits for RAM headroom, and halts on repeated failure. Never merges. |
| `issue-enriching` | Turn a thin GitHub issue into one an agent can pick up cold — ground it in the repo, reach a verdict, append a delimited `## Agent brief` without touching the author's text. `triage`'s counterpart: same grounding core, but it rewrites an existing issue instead of filing a new one. |
| `land` | Carry an open PR to merged behind a deterministic core-path gate that refuses to auto-merge anything touching migrations, CI, auth, or lockfiles. The only skill here that runs `gh pr merge`. |

`nightshift` and `issue-enriching` share their grounding core with `triage` via
`skills/_shared/issue-grounding.md` — the verdict table, the issue-body template,
and the read-only Explore contract live there once.

`one-shot` does not implement the phases itself — it dispatches them. Those
companions ship here too, and are usable standalone:

| Skill | What it does |
|-------|--------------|
| `council-of-agents` | Parallel multi-lens planning amplifier — 3-5 subagents, one lens each, synthesised into a single design brief. |
| `tdd` | Red → green → refactor; the implement phase's testing contract. |
| `code-review` | Parallel-lens review of a diff (local branch or PR) emitting a machine findings packet: must-fix / should-fix / consider / nit. |
| `code-fix` | The receive side of that cascade — consumes the findings packet, applies fixes, commits. |
| `create-commit` | Staged commit with a Conventional Commits message. |
| `create-pr` | Push the branch and open the PR. |
| `diagnosing-bugs` | Diagnosis loop for hard bugs and performance regressions, for when a phase hits one. |

Install `one-shot` without them and the cascade has nothing to dispatch: it
reaches the commit / review / PR phases, finds no skill, and stops without
pushing.

Standalone:

| Skill | What it does |
|-------|--------------|
| `linear-grooming` | Reconcile the Linear issues assigned to you with GitHub PR state — merged → done, open → in review, draft → in progress — and flag stale or ambiguous tickets. Uses the Linear MCP by default or the Linear API with a key; `bin/linear-grooming` runs it on a loop. Needs `bun`. Run `setup.sh` once to set project, repos, team and status names. |

## Standards come from your repo

None of these skills carry an opinion about how your code should be shaped.
`one-shot` reads your `CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md` / `docs/`
once per run, distils a standards brief, and passes it to every agent it
dispatches — so review findings and applied fixes cite *your* rules. Where a
repo declares nothing, the cascade infers the convention from the code it is
changing and says which file it inferred it from, rather than importing a house
style from elsewhere.

## Scope

This repo is published deliberately and reviewed by hand. It is not an automatic
export of a larger private collection; skills are added one at a time.

## License

MIT — see [LICENSE](./LICENSE).

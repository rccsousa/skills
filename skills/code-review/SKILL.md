---
name: code-review
description: >
  Review a diff (local branch vs base, OR an open PR) and produce a structured
  findings packet (must-fix / should-fix / consider / nit). Designed to feed code-fix in a cascade.
  Default mode is **local** — no PR required. Use inside one-shot's review
  phase before pushing, when self-reviewing a branch, or whenever the user asks
  to "review this", "code-review this branch", or "find issues before I push".
  Parallel-lens engine emitting a machine findings packet for the cascade; for
  a single deep human-facing reviewer enforcing the SRP/naming/let-it-fail
  standards, use /surgical-review.
---

# Code Review

Review side of the one-shot review cascade. Reads a diff (local branch vs
base by default; an open PR if a number is passed), classifies findings into
must-fix / should-fix / consider / nit, and emits a structured findings packet that `code-fix`
consumes verbatim.

**Local by default.** Inside one-shot's inner loop, review runs on the
local branch **before** push + PR open — the review catches issues while
fixes are still cheap (no force-push, no thread re-resolution, no public
churn). PR mode is opt-in via a PR-number arg or `--target=pr`.

## When to use

- Self-review of a local branch before pushing (default inside one-shot)
- Reviewing an open PR (pass `<PR-number>` or PR URL)
- Inside `one-shot` review phase
- Any time the user asks to review a branch or PR

Skip for tiny diffs (<50 LOC, single-purpose) — read inline instead.

## Invocation

```
/code-review [PR-number-or-URL] [--diff=<spec>] [--base=<branch>] [--plan=<path>]
           [--post --i-understand-the-risk]
           [--max-parallel=N] [--no-parallel] [--lenses=<csv>]
```

Flags:

- `<PR-number-or-URL>` (positional, optional) — review an open PR. If omitted,
  default to local-branch review.
- `--diff=<spec>` — explicit diff spec (e.g. `main...HEAD`, `HEAD~3..HEAD`,
  `staged`, `worktree`). Overrides everything else.
- `--base=<branch>` — base branch for local diff (default: repo default branch
  resolved via `git symbolic-ref refs/remotes/origin/HEAD`, fallback `main`).
- `--plan=<path>` — compare diff against this plan; flag missing tasks
- `--post` — post findings to GitHub via `gh pr review` (see ⚠️ section below).
  Requires `--i-understand-the-risk` AND an open PR. Refuses in local mode.
- `--max-parallel=N` — cap lens fan-out (default: unbounded — all lenses
  spawn in parallel)
- `--no-parallel` — disable fan-out, run a single review agent (legacy mode)
- `--lenses=<csv>` — override default lens set, comma-separated. Default
  set: `security,correctness,plan-vs-diff,perf,nit,ci-build`.

Default: review output stays local — handed to the user as a draft, or to
`code-fix` as an in-memory packet inside a one-shot cascade. Posting to
GitHub is user-driven (copy/paste, or run `gh pr review` yourself), and only
possible when a PR exists.

## Process

1. **Resolve diff source** (precedence order):
   1. `--diff=<spec>` explicit → use it verbatim
   2. PR number/URL passed → `gh pr diff <number>` (PR mode)
   3. No arg + current branch already has an open PR → `gh pr diff` (PR mode)
   4. Else → **local mode**: `git diff <base>...HEAD` where `<base>` is
      `--base` if set, otherwise repo default branch
2. **Fetch diff once.** Cache for all lens agents. In local mode, also
   fetch `git status --porcelain` and surface uncommitted changes as a
   warning under `lens_warnings` — they aren't part of the diff but the
   reviewer should know.
3. **Read plan if `--plan` given.** Hold a checklist of expected tasks.
4. **Fan out lens agents in parallel** (default; serial if `--no-parallel`). One Agent per lens, all dispatched in a single message:
   - **security** — auth, injection, secrets, AuthZ holes, removed checks
   - **correctness** — bugs, races, swallowed errors, missing tests, broken contracts
   - **plan-vs-diff** — walks plan tasks (if `--plan` given), flags gaps and unimplemented tasks
   - **perf** — hot loops, N+1, unnecessary allocations, sync IO in async paths
   - **nit** — style, comment polish, naming, ordering (record, don't block)
   - **ci-build** — failing checks, lockfile drift, OpenAPI drift, generated-file mismatch
5. **Each lens emits a partial findings packet** scoped to its lens. Same YAML shape as the final, but only items it found.
6. **Merge.** Orchestrator dedups by `file:line`, picks max severity when lenses overlap (must-fix > should-fix > consider > nit), concatenates `why` fields with `;`, picks shortest `fix_hint`.
7. **CI status.** PR mode only — single `gh pr checks <number>` call. Failing
   checks → meta-finding under `merge_blocking`. Local mode → skip (CI status
   is `n/a`).
8. **Emit canonical findings packet.** YAML, sized for direct paste into code-fix.
9. **Surface output.**
   - Default: local draft to the user. No GitHub write actions.
   - `--post --i-understand-the-risk` (see ⚠️ section): PR mode only — post a
     review-level comment summarising findings + one inline `gh pr review-comment`
     per must-fix/should-fix/consider item. Refuses in local mode.

## Parallel fan-out

Default = fan out flat. Six lens agents in a single message, no cap. The
diff is fetched once and passed as input to every lens — they don't each
re-fetch.

```
        [orchestrator]
              │
   fetch diff + plan once
              │
   ┌────┬────┬─┴──┬────┬────┐
   ▼    ▼    ▼    ▼    ▼    ▼
  sec  corr  p-vs-d  perf  nit  ci-build
   │    │    │    │    │    │
   └────┴────┴────┴────┴────┘
              │
        merge + dedup
              │
       canonical packet
```

Throttles:

- `--max-parallel=N` — only N lenses run at a time (rest queue). Default = unbounded.
- `--no-parallel` — single agent handles all lenses sequentially (slower, smaller token spike).
- `--lenses=security,correctness` — narrow lens set to a subset.

Each lens agent gets a prompt that briefs:

1. Its lens (e.g. "you are the security lens — look only for auth/injection/secrets/AuthZ holes")
2. The diff (as text input or via `gh pr diff` re-fetch if context-limited)
3. The plan path (only the plan-vs-diff lens reads the plan)
4. Required return shape (partial YAML packet — same schema, only its findings)
5. "Report under 300 words of explanation outside the packet — packet itself is the deliverable"

Failure handling: if any lens agent errors or times out, the merge still
completes with the other lenses' output, but the orchestrator surfaces a
warning in the packet under `lens_warnings: [<lens>: <reason>]`. Never silently
drop a lens.

## Severity heuristics

| Spot                                                              | Bucket     |
|-------------------------------------------------------------------|------------|
| `eval`, `exec`, untrusted-input concat into SQL/HTML/shell        | must-fix   |
| Auth check removed or weakened                                    | must-fix   |
| Race condition, missing lock on shared state                      | must-fix   |
| Test deleted without replacement covering same path               | must-fix   |
| Plan task not implemented                                         | should-fix |
| Error swallowed (`catch {}` empty, ignored Promise)               | should-fix |
| Broken contract / wrong return shape on internal API              | should-fix |
| Missing test for new non-trivial branch                           | should-fix |
| Public function with ambiguous name + no docstring                | consider   |
| New magic number with no explanation                              | consider   |
| Variable rename inconsistent (some sites missed)                  | consider   |
| Trailing whitespace, import order, `let` vs `const` preference    | nit        |
| Comment polish, typo in identifier (non-public)                   | nit        |

The tier name IS the triage rule: **must-fix** = blocking, fix before merge.
**should-fix** = clear defect, not blocking (high confidence it's wrong), fix
now. **consider** = judgement-call, lower confidence (reasonable people could
defer) — code-fix fixes only the sensical ones. **nit** = trivial.

Tie-breaks, always round up: unsure must-fix/should-fix → must-fix;
should-fix/consider → should-fix; consider/nit → consider.

These four buckets map 1:1 onto the human `Critical/Major/Minor` buckets used by
`/surgical-review`. Same
standards, two output vocabularies: this skill emits the machine packet for
`code-fix`; surgical-review is the single-reviewer human counterpart.

## Standards smell baseline

**House charter first.** For code produced by us (not external PRs), the
`/code-writing-standards` charter is the source of truth — the **correctness**
lens invokes the `code-writing-standards` skill and applies its
Functions / Modules / Seams / Comments rules and review checklist, mapping
violations to severities (SRP/cohesion/temporal-decomposition/single-owner →
should-fix; un-earned prose / HOW-comments / seam-in-pure-core → consider). The
Fowler smells below are the generic backstop underneath the charter, not a
replacement for it. (Deep single-reviewer enforcement of the charter is
`/surgical-review`; this lens is the cascade's machine-packet echo of the same
rules.)

The correctness lens carries this fixed Fowler smell baseline (_Refactoring_,
ch.3) on top of whatever the repo documents (`CODING_STANDARDS.md`,
`CONTRIBUTING.md`). Two binding rules:

- **Repo overrides.** A documented repo standard always wins; where it endorses
  something the baseline would flag, suppress the smell.
- **Always a judgement call.** Each smell is a labelled heuristic ("possible
  Feature Envy"), never a hard violation → lands `consider`, not `must-fix`.
  Skip anything tooling already enforces.

Each reads *what it is* → *fix*; match against the diff:

- **Mysterious Name** — name doesn't reveal what fn/var/type does or holds. → rename; if no honest name comes, design's murky.
- **Duplicated Code** — same logic shape in >1 hunk/file. → extract shared shape, call from both.
- **Feature Envy** — method reaches into another object's data more than its own. → move method onto the data it envies.
- **Data Clumps** — same few fields/params keep travelling together. → bundle into one type, pass that.
- **Primitive Obsession** — primitive/string standing in for a domain concept. → give the concept its own small type.
- **Repeated Switches** — same `switch`/`if`-cascade on same type recurs. → polymorphism, or one shared map.
- **Shotgun Surgery** — one logical change forces scattered edits across many files. → gather what changes together into one module.
- **Divergent Change** — one module edited for several unrelated reasons. → split so each changes for one reason.
- **Speculative Generality** — abstraction/params/hooks for needs the spec lacks. → delete; inline back until a real need shows.
- **Message Chains** — long `a.b().c().d()` the caller shouldn't depend on. → hide the walk behind one method on the first object.
- **Middle Man** — class/fn that mostly just delegates onward. → cut it, call the real target direct.
- **Refused Bequest** — subclass/implementer ignores most of what it inherits. → drop inheritance, use composition.

## Spec axis

Beyond the plan-vs-diff lens, the **spec axis** checks the diff against the
*originating* issue/PRD (not just the plan): (a) requirements asked-for but
missing/partial, (b) behaviour not asked for (scope creep), (c) requirements
that look implemented but wrong. Quote the spec line per finding. Skip + note if
no spec source exists (resolve via `docs/agents/issue-tracker.md`, or the
issue refs in commit messages).

## Findings packet

YAML. Caveman-ultra body strings (terse, fragments OK). Identifiers + paths
verbatim.

```yaml
source: local                      # local | pr
pr: null                           # null in local mode, else PR number
url: null                          # null in local mode, else PR URL
title: feat(auth): rotate refresh tokens
base: main
head: feat/auth-rotate
adds: 142
dels: 23
ci_status: n/a                     # green | red | pending | n/a (local)
plan_file: plans/auth-rotate.md    # null if no --plan
must_fix:
  - file: src/auth/refresh.ts
    line: 42
    summary: replay window unbounded
    why: token timestamp not checked → replay possible
    fix_hint: enforce 5min window per plan §4
should_fix:
  - file: src/auth/handler.ts
    line: 88
    summary: error swallowed in catch
    why: refresh fail → silent 200 res, client never retries
    fix_hint: rethrow or log + 401
  - file: plans/auth-rotate.md
    line: null
    summary: plan task §6 not impl
    why: rate-limit on refresh endpoint missing
    fix_hint: add token-bucket per user
consider:
  - file: src/auth/store.ts
    line: 23
    summary: magic number 900 unexplained
    why: 900 = 15min TTL, no const/comment → unclear intent
    fix_hint: extract REFRESH_TTL_SEC = 900
nit:
  - file: src/util.ts
    line: 12
    summary: let → const
merge_blocking:
  must_fix_count: 1
  should_fix_count: 2
  failing_checks: 0
  plan_gaps: 1
recommendation: fix must-fix + should-fix + sensical consider, defer rest, then ready-for-review
```

The packet feeds `code-fix` directly — no re-discovery.

## ⚠️ `--post` (GitHub write)

`--post --i-understand-the-risk` posts the review to GitHub as the user's `gh`
identity. Used by `one-shot --mode=auto` **only after a PR exists** — the
default cascade reviews locally first, then opens the PR, so `--post` rarely
fires in the inner loop. Posted reviews are visible to teammates immediately,
so this is gated.

**Preconditions — all must hold, else refuse + halt:**

1. Both flags present: `--post` AND `--i-understand-the-risk`.
2. Source is PR mode (PR arg passed or autodetected). Local mode refuses
   `--post` with "no PR to post to — push + open PR first".
3. `.claude/auto-mode-disabled` not present at repo root.
4. `~/.claude/auto-mode-disabled` not present globally.
5. PR is in draft state. Refuse to post on ready-for-review PRs — those should
   get human review, not Claude review.
6. `gh` authed as a single known user.

In `--post` mode:

- Use `gh pr review --comment` for the review-level summary (never
  `--approve` or `--request-changes` — those carry status meaning).
- Use `gh pr review-comment` (NOT `gh issue comment`) for per-line findings.
- Append to `.claude/auto-mode.log`:
  `2026-05-21T14:33:12Z code-review post #1234 1 must-fix, 2 should-fix, 1 consider, 1 nit`.
- Hard cap: never `--approve` or `--request-changes`. Comment-only.

## Halt conditions

- PR mode + PR not found → halt: "PR <ref> not found"
- Local mode + branch == base AND no staged/worktree changes → halt: "no diff
  vs base, nothing to review"
- Diff empty (any mode) → halt: "no changes vs base"
- Plan flag set + file missing → halt: "plan not found at <path>"
- PR mode + `gh` not authed → halt: "run `gh auth login`"
- `--post` set in local mode → halt: "no PR to post to — push + open PR first"
- `--post` set + any other precondition above fails → halt w/ specific reason

## Output style — caveman ultra (under-the-hood)

This skill operates in caveman ultra mode for generated outputs. Token saver,
not presentation choice.

**Apply to:** findings packet body strings (summary, why, fix_hint), the local
draft surfaced to user, handoff notes.

**Do NOT apply to:** code blocks (verbatim), file paths, line numbers, identifiers,
error strings, halt messages.

**Rules:**

- Drop articles (a / an / the), filler (just / really / basically)
- Fragments OK
- Short synonyms: DB not database, auth not authentication, fn not function,
  req not request, res not response, impl not implementation
- Arrows for causality: `X → Y`
- One word when one word suffices
- Code blocks + quoted errors unchanged

Example summary:

- Normal: "The error in this catch block is being swallowed silently"
- Caveman ultra: "error swallowed in catch"

## Out of scope

- Opening the PR → `/create-pr`
- Applying fixes from this review → `/code-fix`
- Merging the PR → user does this manually on GitHub
- Adversarial / red-team review → use a dedicated security review skill

## Why this skill exists

Self-review before pushing catches the easy stuff while fixes are still cheap
— no force-push, no thread re-resolution, no public churn. Inside
`one-shot`, it's the request side of the cascade, running on the **local
branch** before the PR exists. The findings packet is the structured handoff
to `code-fix`.

PR mode (review against an open PR) stays available for standalone use:
self-review before flipping draft → ready, or reviewing someone else's PR.

Severity buckets mirror one-shot's halt conditions so the orchestrator
can decide deterministically whether to halt or proceed.

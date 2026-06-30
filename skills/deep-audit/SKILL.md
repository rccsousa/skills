---
name: deep-audit
description: Audit someone else's branch/PR as an external reviewer — read-only, report-not-fix posture, with a mandatory verification gate so only proven findings reach the client/team. Drives the full loop - scope & cluster the diff, fan out parallel reviewers, collate, verify each finding against source + runtime, reconcile a local report, and optionally emit a ready-to-fire script that posts the verified findings as inline PR review comments. Use when reviewing code you do NOT own or contribute to, when hired to audit, or when credibility of findings is the deliverable. Triggers - "/deep-audit", "audit this branch/PR", "review as an external auditor", "we're guarding not contributing".
disable-model-invocation: true
---

# deep-audit

Put on the auditor hat. You are an **external reviewer** of code you do **not** own. The deliverable is a set of findings the author can trust — not edits, not a merged PR.

**Core principle:** On an audit, a wrong finding costs more than a missed one. You are a guard. Every finding earns its severity by being traced to source and, where behaviour depends on a runtime contract, confirmed by running it.

## Posture — set this first, hold it throughout

- **Read-only.** Do not edit, write, refactor, or commit anything in the audited repo. Inspect only.
- **Report, don't fix.** Even when the fix is obvious. Surface it; let the owner act. (This is the trap in self-review skills like `surgical-review` / `requesting-code-review` — their "fix Critical immediately" posture is wrong here.)
- **Careful before any outward action.** Default to a **local** report. Never post to a PR/GitHub/Slack without explicit per-instance approval — publishing findings about someone else's code is irreversible and reputational.
- **Credibility over volume.** Better to present 2 proven findings than 10 plausible ones. See memory [[verify-review-findings-before-reporting]].

## The loop

```
SCOPE → FAN-OUT → COLLATE → VERIFY ⇄ (re-review) → ADVERSARIAL red-team → RECONCILE → (local report) → [EMIT fire-script]
```

### 1. SCOPE & cluster
- **Get the PR code onto disk first.** The audit reads files at specific lines AND the VERIFY gate *runs* code (`mix`/`elixir`/`node`) — both need a real working tree, not just the diff. From `main` you'd read the wrong (base) version of changed files. So for a remote PR, don't stay on `main`: **prefer a worktree** (isolates the audit, keeps the user's branch clean, posture-safe) — `gh pr checkout <X> --worktree ../audit-pr<X>` or `git worktree add ../audit-pr<X> origin/<pr-branch>`; plain `gh pr checkout <X>` works but switches the current dir. (Firing the review scripts later needs none of this — they hit GitHub by PR number + sha.) Capture the PR's HEAD sha here for the fire-scripts' `COMMIT`. `git worktree remove` when done.
- `git diff <base>...<branch> --stat`. Read the commit log for context — note if the branch was already self-reviewed (residue, not structural debt).
- Cluster the diff by domain (e.g. external-integration boundary, core domain + controllers, auth/access, migrations, frontend). One cluster ≈ one reviewer. Aim 4–6 clusters for a large branch.

### 2. FAN-OUT parallel reviewers
- Dispatch one subagent per cluster (background, in a single message so they run concurrently). Use `superpowers:code-reviewer` or general-purpose.
- Every reviewer prompt MUST carry the posture: **"AUDIT ONLY — not our repo, READ ONLY, do not edit/write/commit, only report findings."**
- Scope each to its file list, give the diff range, demand severity-tagged bullets (🔴/🟠/🟡), `file:line — issue — why it matters`, and cap output (~350 words, bullets only) to protect the orchestrator context.
- Bias the focus per cluster: secrets/HTTP robustness for integrations, money/state-machine for domain, IDOR/auth-bypass for access, prod-lock/data-loss for migrations, money-format/cache for frontend.

### 3. COLLATE
- Gather the tiered bullets into one draft report (CodeRabbit-style: walkthrough + severity table + per-finding block with a handoff each). This draft is **untrusted** — raw reviewer output.

### 4. VERIFY — the gate (mandatory)
- Run `/verify-review-findings` over the draft. For every finding above nit: trace to a *reachable* source path; when the claim hinges on a library/language/runtime contract, **run it** (`elixir`/`node`/`mix run`, `Mix.install` for one dep) or read the lib docs via context7 — never assert from memory. Classify: stands / downgrade / refute, with evidence.
- **This cycles.** Refuting a finding may reveal a real adjacent issue → spawn a targeted re-review (back to a focused FAN-OUT). Loop until findings stabilize.

### 4.5 ADVERSARIAL red-team — fresh eyes try to break the audit (recommended)
The VERIFY gate trusts your own trace, and confirmation bias survives self-verification. So before committing the report, run **`/red-team-findings`** over the surviving set: it hands them to one fresh, independent opus agent whose only job is to **refute** each finding (false-positive / wrong-severity / unreachable), hunt what the audit **missed**, and challenge the "verified clean" claims. Feed it the bare survivor list (`severity + file:line + one-line claim`) and the diff range — **not** the draft report's prose, which would bias it toward agreement. Fold its verdicts into RECONCILE as another *input*, not an oracle: drop/downgrade what it refutes, adopt a MISSED finding only after re-tracing it yourself. See that skill for the prompt spine and output contract.

### Output destination (resolve ONCE, before writing the report or scripts)
All artifacts (report + fire-scripts) land in `<DEST>/deep-audit/<pr-or-branch-slug>/`. Pick `<DEST>` from the `--dest` flag:
- **`--dest rezeki` (default)** → `<repo-root>/rezeki/`. It's in the user's global gitignore, so it never touches tracked code (posture-safe — the read-only rule is about the *codebase*, not an ignored scratch dir), lives in the project tree for easy access, and survives across sessions (unlike `/private/tmp`). **If `<repo-root>/rezeki/` does not exist, ask the user whether to create it** ("create `rezeki/`? it's globally gitignored"). Yes → `mkdir -p` and use it. **No answer / declined → fall back to scratchpad** (don't block the audit on it).
- **`--dest scratchpad`** → the session scratchpad. No prompt. Ephemeral — warn it won't survive the session.
- **`--dest <path>`** → that explicit dir (`mkdir -p`). Use as-is.

Echo the resolved destination once so the user knows where to look.

### 5. RECONCILE
- Rewrite the report in place: update each severity badge + add a verification verdict, fix the summary table and top-line verdict to match survivors, add an honest self-correction note if first-pass counts were inflated, and state verification depth (what was traced+run vs reviewer judgement). If a 4.5 red-team ran, reconcile its verdicts here (drop/downgrade refuted, add adopted misses) and note what it changed.
- Write it to **`<DEST>/deep-audit/<pr-or-branch-slug>/report.md`** (see Output destination above). Stop there unless the user explicitly asks to post or to reformat for a PR.
- **Final CTA — offer to copy the artifact dir to the clipboard.** End the turn by asking the user if they want the destination path pushed to `pbcopy` (so they can open it for human eval). On yes, run `printf '%s' "<DEST>/deep-audit/<pr-or-branch-slug>" | pbcopy` (macOS; use `wl-copy`/`xclip -selection clipboard` on Linux — pick by platform). This hands review back to the human cleanly: report's written, here's where it is, go eval. Skip the CTA only if the user already asked for the path or for a fire-script in the same breath.

### 6. EMIT fire-script (optional, on request)
When the user wants the verified findings posted as a code review, don't post — **generate a "ready to fire" shell script** they run themselves. Each verified finding becomes one inline PR review comment as **flag → finding → description → agent prompt** (the agent prompt is TDD-shaped, surgical-scope, ready to paste to an executor — this repo runs on Claude Code). Write the script alongside the report in the resolved **`<DEST>/deep-audit/<pr-or-branch-slug>/`** (`review-batched.sh`); nothing posts until they run it.

**Emit ONLY the batched-review flavor** — one `gh api repos/$REPO/pulls/$PR/reviews` call (comments array + summary `body` + an `event` verdict). The real code-review UX. It is **all-or-nothing: if any one `line` is outside the diff, the whole review 422s** — so the anchoring rules below are non-negotiable. (Don't emit a per-comment script unless the user explicitly asks for it as a fallback after a batched 422.)
  - The verdict is a `VERDICT` env var that **defaults to the recommended verdict for this audit** — derive it from the highest *surviving* severity: any 🔴 (or unresolved 🟠 the auditor judges blocking) → default `REQUEST_CHANGES`; only nits/by-design left → default `APPROVE`; genuinely ambiguous → `COMMENT`. State the chosen default and its reason in a script comment. Keep `COMMENT`/`REQUEST_CHANGES`/`APPROVE` all overridable via the env var. Inject it with `jq --arg ev "$VERDICT" '… {event:$ev} …'` piped into `gh api … --input -`, building comment/summary bodies as single-quoted heredoc shell vars passed via `jq --arg` (jq handles JSON escaping — no manual `$`/backtick/newline escaping). Validate `VERDICT` against the three allowed values and `exit 1` on anything else. **GitHub rejects `APPROVE`/`REQUEST_CHANGES` on the author's OWN PR (422)** — fine for a true external audit, but a gotcha when auditing your own branch: detect/flag this (the branch is the user's own) and add a loud comment telling them to override with `VERDICT=COMMENT`.

**Anchoring rules — get these right or comments 422 (verify, don't assume):**
- `git ls-files | grep <name>` to confirm **every** file path before writing it. Guessed paths are the #1 failure. (Frontend dirs especially — `assets/` vs `frontend/src/`.)
- An inline comment's `line` **must fall inside a diff hunk.** Check `git diff <base>...<branch> -- <file> | grep '^@@'`. New files show `@@ -0,0 +1,N @@` → any line `1..N` is anchorable. Modified files only expose their hunk ranges.
- A real finding on an **unchanged** line (bug pre-exists, the PR didn't touch it) has **no inline anchor** → fold it into the summary `body` as a note, never an inline comment.
- `side: "RIGHT"` for new/current code. Re-confirm each anchor line maps to the expected code (`sed -n` the line) before locking.
- **Never put an apostrophe or unbalanced quote inside a `${VAR:?message}` word** — bash still tracks quotes in the `:?`/`:-` word, so a lone `'` (e.g. "isn't", "doesn't") opens a quote that never closes → `unexpected EOF while looking for matching }`. Keep these messages quote-free, or use an explicit `if [ -z "$VAR" ]; then echo …; exit 1; fi` guard. (Heredoc bodies are safe — they're single-quoted `<<'EOF'`.) Always `bash -n` the emitted script before handing it over.
- Header vars: `PR="${PR:?set PR=<n>}"`, `COMMIT=<HEAD sha>` (re-grab if they push before firing), and `REPO`. **`REPO` autodetect (`gh repo view`) only works when cwd is the repo — and the script lives in scratchpad, which is NOT a repo.** A blank `$REPO` yields `/repos//pulls/...` → silent `404`. So make it explicit-or-autodetect: `REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}"` then `: "${REPO:?set REPO=owner/name}"`. Tell the user the full run command including REPO (`PR=42 REPO=owner/name bash script.sh`) and that posting works from *their* shell even if the audit sandbox blocks it from yours.

This preserves the read-only posture: the skill emits a script, the human pulls the trigger.

## Definition of done
- Every presented finding is traced to source; every runtime-contract claim was executed or doc-confirmed.
- A fresh adversarial pass (step 4.5) red-teamed the surviving findings; its refutes/downgrades and any adopted misses are reflected in the report.
- Report is internally consistent (table ↔ bodies ↔ verdict).
- Nothing in the audited repo was modified; nothing was posted externally without approval.
- If a fire-script was emitted: every path was confirmed via `git ls-files`, every inline anchor line is inside a diff hunk, unanchorable findings live in the summary body, and the script posts nothing on its own.

## Pairs with
- `/verify-review-findings` — the gate this loop hard-requires (step 4).
- `/red-team-findings` — the independent adversarial pass over the survivor set (step 4.5).
- `superpowers:code-reviewer` / general-purpose subagents — the fan-out finders (step 2).
- `context7-mcp` (library-contract checks).
- `gh api .../pulls/{pr}/reviews` (batched) — the fire-script target in step 6 (per-comment `.../comments` only as an explicit fallback).
- Contrast with `surgical-review` / `request-review` — those assume you OWN the code and will fix/merge it; `deep-audit` assumes you don't and won't.

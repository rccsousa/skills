---
name: improve-skill
license: MIT
description: Review the back-and-forth that just followed a skill invocation and propose enhancements to that skill so the same friction is handled automatically next time. Use when the user says "/improve-skill", "make the skill handle this", "fold this into the skill", or after a skill session wraps and the user wants a retro.
user-invocable: false
---

# Improve Skill

Turn live friction into durable skill improvements. After a skill runs, the conversation usually contains corrections, clarifications, missed steps, or judgment calls the user had to make manually. This skill harvests those signals and proposes edits to the skill file so the next run handles them automatically.

**Core principle:** The transcript is the spec. If the user had to say it once, the skill should say it next time.

## When to Invoke

- Right after a skill session ends and the user wants to capture lessons.
- Mid-session if a clear gap emerged ("the skill should have done X").
- Not for one-off corrections unrelated to skill behavior — those are conversation noise, not skill gaps.

## Procedure

### 1. Identify the target skill

Scan recent conversation for the most recent `Skill` tool invocation (look for the skill name in tool calls or `<command-name>` tags). If multiple skills ran, pick the most recent unless the user named one explicitly.

If ambiguous or none found, ask the user which skill to improve. Do not guess.

Resolve the skill file path:
- Personal skills: `~/.claude/skills/<name>/SKILL.md`
- Plugin skills: search under `~/.claude/plugins/` or the project's `.claude/skills/`
- If the skill has supporting files (templates, prompts), read those too.

### 2. Harvest friction signals from the transcript

Walk the messages after the skill invocation. Look for:

- **Corrections** — "no, not that", "wrong", "stop doing X", "actually do Y"
- **Clarifications the user repeated** — questions the skill should have pre-answered
- **Missed steps** — actions the user had to prompt explicitly that should have been default
- **Manual judgment calls** — branches the user resolved that could be encoded
- **Tool/permission friction** — repeated approvals for the same command pattern
- **Wrong defaults** — values, paths, flags the user overrode
- **Surprises** — moments the user said "huh" or had to investigate the skill's behavior

For each signal, note: what happened, what the skill did/didn't do, what the user wanted instead.

### 3. Filter ruthlessly

Discard:
- One-off context that won't recur (specific file names, ticket IDs, this-task-only constraints).
- Things already in the skill that just weren't followed — that's a model-attention issue, not a skill gap. Unless making them more prominent would actually help.
- User-preference drift better captured as a persistent memory note than skill logic.

Keep:
- Patterns that will recur on the next invocation.
- Defaults the user clearly prefers.
- Steps that were missing entirely.
- Failure modes worth a one-line warning.

If nothing survives the filter, say so plainly and exit. Not every session yields skill improvements.

### 4. Draft the edit

Produce a concrete diff against the skill file(s). Prefer:
- Surgical edits over rewrites — one new line in the right section beats a restructure.
- Adding to existing sections over inventing new ones.
- Concrete instructions ("default to X unless Y") over vague guidance ("be careful with Z").
- Cross-references to memory if the improvement is really user-preference, not skill-logic.

Respect the skill's existing voice and structure. If the skill is terse and bulleted, don't add prose paragraphs.

### 5. Present and wait

Show the user:
- **Signals found** — 2-5 bullets summarizing the friction harvested.
- **Signals discarded** — what you considered but filtered out, with one-line reasons.
- **Proposed edit** — the diff, with file paths and line context.

Then stop and wait for explicit approval. Do not write the file until the user confirms. If the user redirects ("skip the first one", "tighten the wording"), revise and re-present.

### 6. Apply

On approval, use `Edit` to apply the change. If the diff touches multiple files, apply them in one batch. Confirm with a single line: "Updated `<skill>/SKILL.md`."

## Anti-patterns

- **Don't over-engineer.** A skill is not a state machine; it's a prompt. If the fix is one sentence, write one sentence.
- **Don't accumulate dead clauses.** If a new instruction supersedes an existing one, replace it — don't stack.
- **Don't bake in this-session specifics.** Tomorrow's invocation won't have the same issue tracker ticket or branch name.
- **Don't silently rewrite.** Always show the diff and wait.
- **Don't conflate skill gaps with memory gaps.** "User prefers terse PRs" → memory. "Skill should run `gh pr checks` before declaring ready" → skill.

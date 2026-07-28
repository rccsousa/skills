---
name: triage
description: >
  Turn raw tester/user feedback into curated, agent-pickup GitHub issues, one
  item at a time. Feedback arrives two ways: pasted (a message + screenshots) OR
  pulled from a Basecamp inbox column. For each item: parse the complaint, ground
  it in the current repo via a read-only Explore subagent, reach a verdict
  (bug / QoL-feature / not-a-bug / defer / investigation), then file one rich GH
  issue with file:line findings. When sourced from Basecamp, comment the issue URL
  back on the card and move it to a triaged column. Use when the user says
  "/triage", pastes tester feedback, points at a Basecamp feedback column, or says
  "go through this feedback", "open issues from this".
disable-model-invocation: true
---

# Triage

Convert unsorted feedback into curated GitHub issues, one item at a time.

Goal: every actionable piece of feedback becomes a focused issue a cloud agent
can pick up cold — grounded in real `file:line` refs, with a clear verdict, so
nobody re-briefs it later. Issues land in the **current repo** so a
GitHub-connected agent can auto-pick-up and `/one-shot` them.

## When to use

- User pastes a tester message + screenshot(s) and wants it triaged.
- User points at a **Basecamp feedback column** ("triage my inbox", "/triage")
  in a repo whose Basecamp project is wired via `.basecamp/config.json`.
- User says "/triage", "go through this feedback", "open issues from this".
- A batch of feedback items arrives to process one by one.

Skip when the user already knows the exact fix and just wants it done → just do
the work (or use `/one-shot`). Triage is for *unsorted* feedback that needs a
fixable-vs-not call first.

## Input modes

Triage grounds and files identically regardless of source — only how items
**arrive** differs. Pick the mode from context:

| Mode | Trigger | Source |
|------|---------|--------|
| **pasted** | user pastes a message and/or screenshots | the message + attached images |
| **basecamp** | bare `/triage` in a repo with `.basecamp/config.json`, or "triage my Basecamp inbox" | cards in a named feedback/inbox column |

`/triage --from basecamp` forces basecamp mode; `--from pasted` forces pasted.
If a repo has a Basecamp config but the user also pasted text, the pasted text
wins (it's the more specific signal).

### Basecamp mode — pulling the inbox

The Basecamp project is resolved from `.basecamp/config.json` (so `--in` can be
omitted). Process:

1. **Find the inbox column.** `basecamp cards columns --json` (add
   `--card-table <id>` if the project has multiple tables — the ambiguity error
   names them). Pick the feedback/triage/inbox column; if the name is ambiguous,
   ask which column once, then remember it for the batch.
2. **List its cards.** `basecamp cards list --column <id> --json` — each card is
   one feedback item. Process them **one at a time**, oldest first.
3. **Read the card + its screenshots.**
   `basecamp cards show <card_id> --download-attachments --json` — the
   `content_attachments` / `description_attachments` entries come back with a
   local `path`; Read those images the same way you'd read a pasted screenshot.
4. Feed the card title + body + images into the loop below exactly as if pasted.

## The loop (per feedback item)

If several items are queued at once, ground them **in parallel** (one Explore
agent per item) — they're independent. Filing/commenting stays sequential.
Parallel means *several `Agent` calls in one message*, never background agents —
see the grounding step.

### 1. Parse

Restate the complaint/request in one or two crisp lines. Name the exact screen /
feature. Separate the *symptom* (what the tester saw) from the *ask* (what they
want). Note any positive signal (e.g. "send was fast") so it isn't mistaken for
a bug. Strip duplicate or stretch sub-asks the tester themselves hedged on
("IDK", "maybe", "defer to X").

### 2. Ground (read-only Explore subagent)

Follow `~/.claude/skills/_shared/issue-grounding.md` §1–2 — orient to the repo,
then spawn a capped read-only `Explore` agent for `file:line` findings.

This step is what makes the issue agent-pickup-ready. Don't skip it.

### 3. Verdict

Classify before writing anything, per the verdict table in
`~/.claude/skills/_shared/issue-grounding.md` §3 (bug / QoL-feature / not-a-bug /
defer / investigation), including the **density gate**.

If scope is genuinely ambiguous (e.g. QoL-only vs build a big feature), use
`AskUserQuestion` with a recommended option first. Otherwise pick the obvious
call and proceed — say which.

### 4. File the issue

Use the body template in `~/.claude/skills/_shared/issue-grounding.md` §5. Write
the body to a temp file and create via `gh` on the **current repo** (no `--repo`
flag needed — `gh` uses the repo you're in):

```
gh issue create --title "<conventional title>" \
  --label <bug|enhancement> [--label <extra>] --body-file <tmpfile>
```

Labels per `_shared/issue-grounding.md` §4.

### 5. Close the loop on the card (basecamp mode only)

After the issue is filed, link it back and clear the board with one call:

```bash
bash ~/.claude/skills/triage/lib/close-card.sh <card_id> <issue-url> \
  --to "<Triaged column>" [--card-table <table_id>] [--in <project>]
```

It always comments the issue URL, then moves the card **only** if `--to` is
given. A failed move (column unresolved) keeps the comment and reports
`move-failed` rather than erroring. Machine line:
`CARD <card_id> <commented|comment-failed> <moved|move-failed|no-move>`.

You still own the board judgment: resolve the Triaged/In-progress column id
once (`basecamp cards columns`) and reuse it across the batch. If no such
column exists, omit `--to` (comment only) — don't invent board structure.

### 6. Report

One terse line back: verdict + issue URL (+ card moved, in basecamp mode). Keep a
running tally across the batch.

## Issue body, conventions, anti-patterns

All three live in `~/.claude/skills/_shared/issue-grounding.md` §5–7 — shared with
`/issue-enriching`. In basecamp mode, link the source card URL in `## Context`.

## Anti-patterns (triage-specific)

- **Basecamp mode:** filing the issue but forgetting to comment + move the card —
  the board silently drifts out of sync. Always close the loop (step 5).
- **Basecamp mode:** re-triaging cards already moved to the Triaged column. Only
  process the inbox column.

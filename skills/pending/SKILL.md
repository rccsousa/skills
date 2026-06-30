---
name: pending
description: Track and surface pending todo items across sessions via a checkbox-tracked memory file. Triggers - "/pending", "what's pending", "what do I need to do", "cross X off", "mark X done", "add X to pending".
---

# pending

Single source of truth: `<project-memory-dir>/pending_active.md`. The memory dir is the one shown in the session's global instructions (e.g. `~/.claude/projects/<sanitized-cwd>/memory/`). All operations are deterministic markdown edits — no LLM creativity in the storage layer.

## File format

```markdown
---
name: pending-active
description: Active pending items, checkbox-tracked. Surface when user asks "what's pending".
metadata:
  type: project
---

## Active

- [ ] <id> — <title>.
  **Why:** <reason>.
  **Surface:** <YYYY-MM-DD | anytime>.

## Archive

- [x] <id> — <title>. (done <YYYY-MM-DD>)
```

`<id>` = short kebab-case slug (e.g. `team-offsite`, `webhook-emit`). Derive from title if user doesn't supply.

## Operations

### `list` (default — "what's pending")

1. Read `pending_active.md`.
2. Print **Active** items whose `Surface` is `anytime` or ≤ today.
3. Hide future-dated items unless user asks "show all pending".
4. If file missing → reply `No pending items.` and stop.

Output format: bulleted list, one line per item — `**<id>**: <title>` + a short `why` clause. Don't dump the full Why blob unless asked.

### `add <title>` ("add X to pending")

1. Derive `<id>` from title (kebab-case, ≤30 chars). If collision in Active, suffix `-2`.
2. Append under `## Active`:
   ```
   - [ ] <id> — <title>.
     **Why:** <reason if user gave one, else "(captured <today>)">.
     **Surface:** <anytime unless user specified a date>.
   ```
3. Reply `added: <id>`.

### `check <id>` / "cross X off" / "mark X done"

1. Locate the `- [ ] <id> ...` block in **Active**. If user gives a fuzzy phrase (`offsite`), match on `<id>` substring then on title text. Ambiguous → list candidates, ask which.
2. Flip the checkbox: `- [ ]` → `- [x]`.
3. Move the line + its `**Why:**` / `**Surface:**` continuation lines out of Active into **Archive** as a single condensed line:
   `- [x] <id> — <title>. (done <today>)`
4. Reply `crossed: <id>`.

Use `Edit` tool, not regex/sed. Read the file first, then two `Edit` calls (remove from Active, insert at top of Archive). Don't `Write` the whole file unless reformatting.

### `clear-archive`

Drop Archive entries dated >14 days ago. Keep ordering newest-first.

### `surface <id> <date>`

Update an existing Active item's `Surface:` line to the given date (or `anytime`).

## MEMORY.md index

Ensure `MEMORY.md` (in the same memory dir) has exactly one line pointing at this file:

```
- [Active pending](pending_active.md) — surface when user asks what's pending
```

If absent, add it under the `## Project` section. If a stale date-bound entry exists (e.g. `pending-2026-05-19`), remove that line and delete the orphan file.

## Conventions

- Dates are absolute (`2026-05-19`), never relative (`tomorrow`, `next week`). Convert at write time.
- One item = one logical action. Multi-step work belongs in a plan, not here.
- If the user asks for status of a known long-running thing (PR open, CI green) — check live state first, then update the pending item accordingly. Don't quote stale Archive lines as current truth.

## Out of scope

- Long-form project context → separate memory file with type=project.
- Cross-project tracking — this is per-project; each project memory dir has its own list.
- Recurring tasks → use `/schedule` or `/loop`.

---
name: dream
license: MIT
description: Use when the user says /dream or asks to consolidate, clean up, or review memories — performs a full memory consolidation pass as a background subagent
user-invocable: false
---

# Dream — Memory Consolidation

Run a subagent that reviews all memory files, scans recent session transcripts for unrecorded learnings, and consolidates the memory system.

## When to Use

- User says `/dream` or asks to consolidate/clean up memories
- Memory index (MEMORY.md) is growing unwieldy
- After a burst of sessions where memories may have been created hastily

## Process

Spawn a **single subagent** with the prompt below. The subagent does ALL the work — do not perform any memory operations yourself.

### Subagent Prompt Template

Adapt paths if the user's project memory directory differs.

```
You are performing a memory consolidation pass ("dream") for the user's Claude Code memory system.

## Paths

- Memory directory: {MEMORY_DIR}
- Memory index: {MEMORY_DIR}/MEMORY.md
- Session transcripts: {PROJECT_DIR}/*.jsonl

## Phase 1: Orient

1. Read MEMORY.md to get the full index of existing memories.
2. Read every memory file listed in the index. Note each file's type, content, and last-modified date.
3. Flag any index entries that point to missing files, or files that exist but aren't indexed.

## Phase 2: Gather Signal from Recent Sessions

1. List all *.jsonl transcript files in the project directory, sorted by modification time (newest first).
2. Read the 5 most recent transcripts. For each, extract ONLY:
   - User corrections or preferences ("don't do X", "always do Y")
   - Confirmed approaches the user validated ("yes exactly", "perfect")
   - Project decisions, deadlines, or context shared by the user
   - References to external systems (Linear, Slack, Grafana, etc.)
   - New workflow patterns the user demonstrated
3. Skip: code output, tool results, system prompts, command output — only user messages and assistant responses that reveal intent or preference.
4. Compare findings against existing memories. Identify:
   - New learnings not yet captured
   - Existing memories that need updating with fresh detail
   - Memories that contradict what recent sessions show

## Phase 3: Consolidate

For each finding from Phase 2:

**New learning** → Create a new memory file with proper frontmatter (name, description, type). Add an entry to MEMORY.md.

**Update needed** → Edit the existing memory file in place. Update the description in frontmatter if it changed. Update the MEMORY.md entry if the one-line hook changed.

**Contradiction** → Trust the most recent signal. Update the older memory. If a memory is fully obsolete, delete the file and remove its MEMORY.md entry.

**Merge candidates** → If two or more memories cover the same topic (e.g., two feedback memories about curl usage), merge them into one file. Remove the redundant file(s) and update MEMORY.md.

### Memory file format
```
---
name: {{name}}
description: {{one-line description}}
type: {{user|feedback|project|reference}}
---

{{content}}
```

### MEMORY.md entry format
Each entry is one line, under 150 chars:
```
- [Title](filename.md) — one-line hook
```

## Phase 4: Prune & Verify

1. Re-read MEMORY.md after all changes.
2. Ensure total line count is under 200. If over, merge or remove the least valuable entries (project memories decay fastest — check if still relevant).
3. Verify every entry in MEMORY.md points to an existing file.
4. Verify every memory file in the directory is indexed in MEMORY.md (except MEMORY.md itself).
5. Report a summary of changes: files created, updated, merged, deleted, and final line count.

## Rules

- NEVER delete a feedback memory unless it directly contradicts a newer, explicit user correction.
- NEVER fabricate memories — only record what the user actually said or confirmed.
- Convert relative dates to absolute dates (e.g., "last Thursday" → "2026-04-02").
- Keep MEMORY.md sorted semantically by topic, not chronologically.
- Do NOT save code patterns, architecture, or anything derivable from reading the codebase.
- Do NOT save anything already in CLAUDE.md files.
```

## Invocation

When the user triggers this skill:

1. Determine the memory directory and project directory paths.
2. Spawn the subagent using the Agent tool with the prompt above (fill in paths).
3. When the subagent completes, relay its summary to the user.

```
Agent({
  description: "Memory consolidation dream",
  prompt: "<filled prompt from template above>",
  run_in_background: true
})
```

Running in background is recommended so the user can continue working.

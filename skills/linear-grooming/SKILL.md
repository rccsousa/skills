---
name: linear-grooming
description: Groom your Linear tickets — walk every open issue assigned to you in a project, check its PRs on GitHub, and move it to the status the evidence supports (in progress / in review / done). Use when the user says "/linear-grooming", "groom my tickets", "sync Linear with my PRs", or "clean up my Linear board".
disable-model-invocation: true
---

Logic lives in `lib/linear-grooming.ts`; you only fetch/write Linear via MCP and relay. Don't re-derive decisions.

`G=<this skill's base directory>/lib/linear-grooming.ts`

First run on a machine: `bash <skill dir>/setup.sh` (user runs it — it's interactive).

## Args

- `--project P` → name in `~/.config/linear-grooming/projects.json` (`{dir, repos, team, statuses}`) or a directory. Default: cwd's repo. Pass through to every `bun $G` call.
- `--api` → Linear GraphQL instead of MCP (needs key; exit 2 = no key → relay setup text, stop).
- `apply` → unattended: apply `safe` rows without asking. Otherwise show table and wait.

## MCP flow (default)

Linear MCP tools below are named `list_issues` / `get_issue` / `save_issue`; use whatever prefix your Linear MCP server has.

1. `bun $G project [--project P]` → `{team}`.
2. `list_issues` with `assignee: "me"`, `team` (omit if null), `limit: 250`, fields `["title","status","statusType","parentId"]`. Page with `cursor`. Write the raw results (array of page objects) to `<tmp>/issues.json` with Write — no hand-editing. `<tmp>` = session scratchpad if you have one, else a temp dir.
3. `bun $G plan --issues <tmp>/issues.json [--project P]`
   - Exit 3 + `NEEDS ID...` → for each ID, in parallel: `get_issue` (collect GitHub PR attachment URLs) and `list_issues` `parentId: ID`, fields `["status","statusType"]`. Write `<tmp>/enrich.json`:
     `{"ENG-1": {"attachments": ["https://github.com/…/pull/1"], "children": [{"identifier": "ENG-2", "state": {"name": "Done", "type": "completed"}}]}}`
     — every NEEDS id present, empty arrays when none. Re-run with `--enrich <tmp>/enrich.json`.
4. Relay the table verbatim.
5. On approval (or `apply` arg): `bun $G apply <safe|all|1,3,5>` → prints `{"id","state"}` lines → one `save_issue` `{id, state}` each, in parallel. Report `ok`/`FAIL` per ID.

## API flow (`--api`)

```bash
bun $G plan --api [--project P]
bun $G apply <safe|all|1,3,5>     # mutates directly
```

## Rules

Flags never applied — relay, the user decides. Unattended: `safe` only; `ask` rows and flags go in the report. Only status changes; never comments, labels, assignee, cycle. Decision rules: `decide()` in `$G`.

Loop launcher: `linear-grooming [--project P] [--api|--mcp] [--every 1h] [--once]` (linked by setup).

---
name: audit-skills
description: Audit Claude skills for visibility flags, deterministic-vs-AI steps, and cross-skill duplication. Use when user says "/audit-skills", "review my skills", "skill audit", or after adding new skills.
---

# audit-skills

Periodic audit of `~/.claude/skills/`, project `.claude/skills/`, and any plugin marketplaces. Produces a changelog of proposed rewrites. Does NOT auto-apply — always show user first.

## Inputs (auto-discover)

- `~/.claude/skills/*/SKILL.md`
- `<project-root>/.claude/skills/*/SKILL.md`
- `~/.claude/plugins/marketplaces/*/.../SKILL.md`

## Three audit axes

### 1. Visibility flags

For each skill, decide two flags:

| Flag | Add when |
|------|----------|
| `disable-model-invocation: true` | High-risk side effects: commit, push, deploy, send msg, mutate shared state, financial op, irreversible delete |
| `user-invocable: false` | Pure background knowledge Claude consults internally; user would never type `/<name>` |

Frontmatter pattern:
```yaml
---
name: <name>
description: <desc>
disable-model-invocation: true   # only if A1
user-invocable: false            # only if A2
---
```

Red flags to scan in skill body:
- `git commit`, `git push`, `gh pr create`, `gh pr merge`
- `DELETE FROM`, `DROP`, `TRUNCATE`, `rm -rf`, worktree remove
- `curl -X POST` to live gateway / external API
- "deploy", "release", "publish"

### 2. Deterministic → script

For each skill, find steps that are fixed/mechanical and replace AI interpretation with a script in the skill folder.

Candidates:
- Multi-step shell pipelines with no judgement (gh queries + jq filters)
- SQL state inspection / cleanup with known table list
- Polling loops (poll until status X, with timeout)
- Verification matrices (run N checks, output JSON pass/fail)
- Templated entity creation (curl + randomize fields)

Pattern: extract into `<skill>/lib/<name>.sh` (or `.ts` if heavy). Skill body invokes the script and reasons over its output. Keep AI for: conflict resolution, scope judgement, edge-case decisions, prose generation.

### 3. Cross-skill duplication

Find pairs/groups with overlapping logic. Extract into either:
- **Shared script** in a common location (`~/.claude/lib/` or `<project>/.claude/lib/`)
- **Smaller composable skill** that other skills reference

Common dup patterns to scan for:
- Same git/PR verification across `pr-ready` / `feature-flow` / `review-*`
- Same worktree state inspection across `housekeeping` / `feature-flow` / `catch-up-*`
- Same gateway-curl template across `create-*` skills
- Same merge/rebase decision table across `catch-up-*` variants
- Global vs project skill with same name → confirm if both still needed

## Output

Three sections, terse:

```
## A — Visibility
A1 disable-model-invocation: <skill> — <reason>
A2 user-invocable:false: <skill> — <reason>

## B — Script extraction
<skill>: <step> → <script-name> (<what it does>)

## C — Dedup
<skill1> + <skill2>: shared <X> → extract <target>
```

Plus a changelog block:
```
## Changelog
- <skill>: +disable-model-invocation (commits/pushes)
- <skill>: extracted <step> → lib/<name>.sh
- <skill1>+<skill2>: deduped <X> → lib/<shared>.sh
```

## Process

1. List all skill dirs (find or ls).
2. Dispatch Explore subagent (cap output ~1500 words) to read every SKILL.md and produce the three lists. Keeps main thread light.
3. Synthesize → show user the changelog.
4. Wait for approval per category (visibility flags = mechanical, safe to bulk-apply; scripts + dedup = bigger surgery, do one at a time).
5. Apply approved edits. For new scripts, create stub + reference from skill body. Don't break working flows on first pass.

## Don't

- Don't auto-edit skills. User reviews changelog first.
- Don't print full diffs of skill rewrites — show frontmatter additions + table summary only.
- Don't bundle visibility + scripts + dedup into one PR. Three separate passes.
- Don't extract scripts speculatively. Only when 2+ skills share the logic, or the step is clearly mechanical with no judgement.

## Cadence

Run after:
- Adding 3+ new skills
- Any new skill that touches commit/push/financial state
- User asks "should I clean up my skills"
- Quarterly (calendar reminder optional)

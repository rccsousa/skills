# Review output contract

Shared output structure + rules for code-review skills (`surgical-review`, `review-codex-pr`, `feature-flow` review phase). Skill-specific lenses (coding standards vs grumpy-Codex vs council) layer on top.

## Severity buckets

| Bucket | Meaning | Action |
|---|---|---|
| **Critical** | Bug, security gap, data-loss risk, broken functionality | Block merge, fix before proceed |
| **Major** | SRP violation on hot path, name blocking understanding, defensive guard on internal contract, missing test for the bug scenario, scope creep | Block merge |
| **Minor / nit** | Style, optimization opportunity, doc tweak, nit-level naming | Note only — skip by default |
| **Strengths** | What's well done, file:line | Acknowledge |
| **Followup risks** | Out-of-scope issues to track | Surface in chat, do NOT `gh issue create` |

## Hard rules

**DO**
- Cite **file:line** for every finding.
- Walk the bug scenario / feature flow step-by-step against the actual code; verify load-bearing assumptions against files, not the brief.
- Read surrounding handlers/callers — not just the hunk.
- Categorize by actual severity. Not everything is Critical.
- Give a clear verdict (Ready / With fixes / Not ready).
- Acknowledge strengths.

**DON'T**
- Auto-post to GitHub. Default = local draft. Submitted reviews can't be deleted.
- Propose `gh issue create` for followups.
- Mark nits as Critical/Major to look thorough.
- Suggest defensive guards on internal contracts (let-it-fail principle — internal callers should crash loudly on contract violations).
- Suggest WHAT-comments to "improve readability" — recommend rename/restructure instead.
- Bundle followup design bugs as blockers on a surgical-fix PR.
- Review diff in isolation without reading surrounding handlers/callers.
- Pad with generic "add more tests / consider edge cases" without naming the specific case.

## Verdict format

```
Verdict: <Ready to merge | With fixes | Not ready>
Reasoning: <1-2 sentences>
```

## Output skeleton

```
### Verdict
<as above>

### Critical
- file:line — what's wrong — why it matters — how to fix (if non-obvious)
(or "None")

### Major
- <same shape>

### Minor
- file:line — one line each (record only)

### Strengths
- file:line — what's well done

### Followup risks
- <issue> — out of scope — surface for tracking (no gh issue)
```

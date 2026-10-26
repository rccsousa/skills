---
name: mermaid-diagram
description: Draw a Mermaid diagram of a flow or a proposed change, rendered and as copyable source, with the parts the proposal changes highlighted in yellow. Use for /mermaid-diagram or when asked to diagram a flow, ticket or proposal.
---

# Mermaid diagram

Produce one diagram that a reviewer can read at a glance and paste into GitHub, Linear, Notion or a PR. Deliver it twice: rendered, and as Mermaid source.

## 1. Pick the diagram type

- **Default to `sequenceDiagram`** for anything with actors talking to each other over time: API calls, webhooks, cron jobs, workers, a user and a dashboard.
- Use `flowchart` only for pure decision logic with no actors, `stateDiagram-v2` for a status lifecycle, `erDiagram` for data models.
- If the user names a type, use it. Do not produce extra diagrams nobody asked for.

## 2. Ground it in the real code

Before drawing, read the code or ticket the diagram is about. Use real names: participants are the actual services, jobs and tables; messages name the real endpoint, function, event, status or error code. Never invent behaviour; if something is inferred, say so in the reply, not in the diagram.

## 3. Structure (sequence diagrams)

- `autonumber` so people can refer to "step 8".
- Short participant aliases: `participant SW as sweepExpired (cron 1 min)`; `actor` for humans/clients.
- A shared preamble first (the steps every case goes through), then one `alt` / `else` branch per case or outcome, each labelled with a plain-language case name (`alt 1. Quote never locked`).
- `Note over X` for outcomes (what the user sees, which status is set). `->>` for calls, `-->>` for responses, `X->>X` for an internal decision.
- Keep messages under ~70 characters; split into two messages instead of cramming.
- Do not use `;` or `#` inside message or note text (they break parsing). Use `<br/>` for a line break inside a note.

## 4. Highlight what changes in yellow

When the diagram shows a proposal or a diff against today's behaviour:

1. Make default notes neutral grey so yellow only ever means "changes". First line of the diagram:
   ```
   %%{init: {"themeVariables": {"noteBkgColor": "#eef1f4", "noteBorderColor": "#b8c2cc", "noteTextColor": "#16202a"}}}%%
   ```
2. Wrap every changed message or note in a yellow block:
   ```
   rect rgba(250, 204, 21, 0.35)
       SW->>DB: CHANGES: step 1 fails with transfers-9212 (was 9204)
   end
   ```
For flowcharts, apply a yellow `classDef` to changed nodes. For state or ER diagrams, use styling supported by that diagram type and renderer; if yellow highlighting is unavailable, label changed elements explicitly and disclose the limitation. Sequence `rect` blocks apply only to sequence diagrams.

3. Start changed text with a marker in the user's language (`CHANGES:` / `MUDA:`) and say what it was before (`(was X)` / `(era X)`).
4. Where a branch deliberately stays the same, end it with a grey note such as `no change: Failed, red` so the reader knows it was considered.

## 5. Validate by rendering

Always render before delivering. Mermaid CLI catches syntax errors and you get to look at the result:

```
npx -y @mermaid-js/mermaid-cli@11.4.2 -i diagram.mmd -o diagram.svg -b white
```

If Chromium is not where Puppeteer expects it, pass `-p puppeteer.json` with `{"executablePath": "<path to chromium>"}`. Keep the browser sandbox enabled; use the environment's documented rendering setup when available. Also render a PNG (`-o diagram.png -w 1400`) and look at it once: check that labels don't overlap and that only changed parts are yellow. Fix and re-render once if needed.

## 6. Deliver

- **Rendered:** a page (or image) showing the SVG on a white background, a one-line legend ("Yellow: what changes with the proposal"), and below it the Mermaid source in a code block with a copy button. Publish a shareable page only when the user authorizes publication; otherwise attach the SVG/PNG.
- **Source:** also give the `.mmd` text (or a fenced ```` ```mermaid ```` block in Markdown) so it can be pasted into GitHub, Linear or Notion, which render it natively.
- Keep any other existing pages or diagrams the user already has; publish this as its own page unless they ask to replace one.
- In the reply: link the rendered artifact and source, and say in one line what the yellow parts are. If rendering is unavailable, provide the source and report that visual validation is incomplete; do not claim it rendered.

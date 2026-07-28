# Intake source adapter contract

An intake source is the queue the pipeline pulls work from. Basecamp columns,
GitHub issues, a Linear view — all reduce to the same five verbs plus a set of
YAML blocks. Adding a source touches nothing outside its own folder.

```
sources/<name>/
  configure.sh            interactive, install-time only
  list.sh                 enumerate the queue
  fetch.sh <id>           item content + attachments, for the agent
  resolve.sh <id> ...     write back: comment + move
  verify.sh               how many items still sit in the queue
  source.md               what the source is, and its role vocabulary
  blocks/*.txt            YAML fragments spliced into the templates
```

## Roles, not columns

The templates never name a column or a label. They name a **role**, and the
adapter maps each role onto whatever the source actually has.

| Role | Meaning | Basecamp | GitHub Issues |
|------|---------|----------|---------------|
| `queue` | human-gated pickup queue; the ONLY thing stage 1 reads | "Agent Triage" column | `needs-triage` label |
| `ready` | item was filed as an agent-ready issue | "Agent ready" column | `agent-ready` on the item |
| `flagged` | suspicious, or still an epic after answers | "Flagged by agent" column | `wontfix` + comment |
| `awaiting` | epic parked pending human answers | "Awaiting answers" column | `needs-info` label |
| `progress` | agent claimed the issue (stage 2) | "in progress" column | — |
| `review` | draft PR exists (stage 2 finaliser) | "In review" column | — |

A source that has no meaningful mapping for a role omits it; the corresponding
block is then empty and the step becomes a no-op. Board updates are always
best-effort — a source hiccup must never abort a run.

## The verbs

**`list.sh`** → JSON array of item ids on stdout, e.g. `[123,456]`. Ids must be
scalars the workflow can safely put in a matrix. Anything malformed must yield
`[]`, never a partial list — a failed listing recovers on the next tick, a
half-listing silently drops work.

Guard every CLI read with a slurp: a CLI that prints and *then* dies emits two
JSON documents, and a streaming `jq` turns that into a multiline value that
corrupts `$GITHUB_OUTPUT`. Use `jq -s -c 'last // []'`.

**`fetch.sh <id>`** → the item's title, body and attachments, with any images
downloaded to local paths the agent can `Read`. This output reaches the model —
it is DATA, and the prompt frames it as such.

**`resolve.sh <id> <outcome> [issue-url]`** → comment the outcome marker on the
item and move it to the role the outcome implies. Outcomes: `filed`, `flagged`,
`questioned`. Prints one machine line:

```
ITEM <id> <commented|comment-failed> <moved|move-failed|no-move>
```

A failed move must keep the comment and report `move-failed` rather than
erroring — the drain gate is what escalates, not this script.

**`verify.sh`** → the number of items still in the queue, or `-1` if the count
itself failed. `-1` fails the drain gate closed. This is the gate that catches
"the agent exited 0 but never actually moved the item".

**`configure.sh`** → install-time only, interactive. Discovers what the source
already has, proposes a role→id mapping, offers to create anything missing, and
emits the `source_env` entries for `.github/maintainer.json`. Never writes YAML.

## Terminal markers

Stage 1's prefilter resolves already-handled items in bash, with no Claude
session at all. It needs to recognise, from an item's existing comments:

- a **filed** marker → route to `ready`
- a **skipped** marker → route to `flagged`
- a **questions** marker is deliberately NOT terminal — it means a human
  answered and returned the item, so it must reach an agent for full re-triage

Declare the exact marker strings in `source.md`. They are matched with `grep -F`
against comment text, so they must be stable and distinctive.

## Blocks

`blocks/<NAME>.txt` holds a YAML or shell fragment spliced into a template at a
`{{BLOCK:<NAME>}}` line. Fragments carry their own indentation and are inserted
verbatim, with `{{SCALAR}}` placeholders substituted from `.vars`.

Required by the stage-1 template: `SOURCE_ENV_TRIAGE` (generated),
`SOURCE_INSTALL_RUN`, `SOURCE_EGRESS`, `SOURCE_LIST_RUN`, `SOURCE_TRIAGE_PROMPT`,
`SOURCE_VERIFY_RUN`. Stage 2 additionally needs `SOURCE_ENV_IMPLEMENT`,
`SOURCE_CLAIM_HOOK`, `SOURCE_DONE_HOOK`. Stage 3 needs none — it never touches
the source.

**No literals.** No account id, project id, column id, handle or address may
appear in a block. They come from the target repo's `maintainer.json` via env
vars. `lib/leak-check.py` enforces this.

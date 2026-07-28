# Basecamp adapter

Pulls cards from a human-gated column of a Basecamp card table. Requires the
[`basecamp` CLI](https://github.com/basecamp/basecamp-cli) and a `BASECAMP_TOKEN`
secret. The token is **account-wide** — it can reach every project the owner can,
which is why stage 1 runs behind an egress firewall and frames all card content
as untrusted data.

## Role mapping

| Role | Column | `maintainer.json` key |
|------|--------|------------------------|
| queue | the pickup column a human drags scoped cards into | `BASECAMP_QUEUE_COLUMN` |
| ready | filed cards land here | `BASECAMP_READY_COLUMN` |
| flagged | suspicious, or still-epic after answers | `BASECAMP_FLAGGED_COLUMN` |
| awaiting | questioned epics await human answers | `BASECAMP_AWAITING_COLUMN` |
| progress | agent claimed the issue (stage 2) | `BASECAMP_PROGRESS_COLUMN` |
| review | draft PR exists (stage 2 finaliser) | `BASECAMP_REVIEW_COLUMN` |

Also required: `BASECAMP_ACCOUNT_ID`, `BASECAMP_PROJECT`, `BASECAMP_CARD_TABLE`,
`BASECAMP_CLI_VERSION`, `BASECAMP_CLI_SHA256`.

The CLI tarball is checksum-verified on every install. **Bump `BASECAMP_CLI_SHA256`
whenever `BASECAMP_CLI_VERSION` changes** — take it from the release's
`checksums.txt`. A stale sha fails the install step loudly, which is the intent.

## Terminal markers

| Marker | Meaning | Prefilter routes to |
|--------|---------|---------------------|
| `🔗 Filed:` | issue already exists | ready |
| `⏭️ Skipped:` | suspicious, or too large | flagged |
| `❓ Questions:` | **not terminal** — human answered, needs full re-triage | (hands to an agent) |

A card carrying both `⏭️ Skipped:` and `🔗 Filed:` resolves as skipped: the skip
marker is the later, terminal verdict.

## Card-to-issue back-reference

Every issue filed from a card ends with a hidden marker:

```
<!-- basecamp-card:<id> -->
```

Stage 2 greps this out of the issue body to move the card to `progress` on claim
and to `review` once the draft PR exists. Without it the board silently stops
tracking the pipeline — the issue and PR are still fine, so this is best-effort,
never load-bearing.

## Ordering trap

The card must **leave the queue column** every run. A comment is not enough:
moving the card is what makes re-triage impossible. The drain gate re-counts the
column after all matrix legs finish and fails loud if anything remains — an
agent exiting 0 is not evidence the board changed.

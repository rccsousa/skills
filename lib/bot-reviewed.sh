#!/usr/bin/env bash
# bot-reviewed.sh <PR#> [copilot|coderabbit]
# Read-only per-tick poll shared by mergeable-loop and drive-to-mergeable.
# Fuses pr-checks.sh readiness with external-bot-posted detection and emits a
# single merge-readiness verdict. Mutates NOTHING — safe on a bare interval.
#
# Verdict (matches the mergeable-loop Tick table exactly):
#   DONE      ready == true AND bot review posted
#   ESCALATE  bot posted AND (unresolved threads > 0 OR CI genuinely red)
#   WAIT      anything else (bot not posted yet, CI pending, fix re-running)
#
# CI "red" = a check in the fail/cancel bucket. Pending is NOT red → WAIT, so a
# just-pushed fix with re-running checks doesn't false-trigger ESCALATE.
#
# Output JSON: { pr, bot, bot_posted, ready, unresolved_threads,
#                ci: {ok, red, pending, failing, total}, head_sha, verdict }
# Exit 0 always; caller branches on .verdict.
set -euo pipefail

PR="${1:?usage: bot-reviewed.sh <PR#> [copilot|coderabbit]}"
BOT="${2:-copilot}"
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$BOT" in
  copilot)    MATCH="copilot" ;;
  coderabbit) MATCH="coderabbit" ;;
  *) echo "unknown bot: $BOT (want copilot|coderabbit)" >&2; exit 2 ;;
esac

# Full readiness report (owns .ready, .review.unresolved_threads).
CHECKS=$(bash "$LIB/pr-checks.sh" "$PR")
READY=$(jq -r '.ready' <<<"$CHECKS")
UNRESOLVED=$(jq -r '.review.unresolved_threads' <<<"$CHECKS")

# Bot review posted?
BOT_POSTED=$(gh pr view "$PR" --json reviews \
  --jq "[.reviews[].author.login] | any(ascii_downcase | contains(\"$MATCH\"))" 2>/dev/null || echo false)

# CI red vs pending — bucket granularity pr-checks.sh collapses.
CHECK_ROWS=$(gh pr checks "$PR" --json bucket 2>/dev/null || echo '[]')
CHECK_ROWS=${CHECK_ROWS:-[]}
CI_RED=$(jq '[.[] | select(.bucket=="fail" or .bucket=="cancel")] | length' <<<"$CHECK_ROWS")
CI_PENDING=$(jq '[.[] | select(.bucket=="pending")] | length' <<<"$CHECK_ROWS")

HEAD_SHA=$(gh pr view "$PR" --json headRefOid --jq '.headRefOid' 2>/dev/null || echo "")

# Verdict.
if [ "$READY" = "true" ] && [ "$BOT_POSTED" = "true" ]; then
  VERDICT="DONE"
elif [ "$BOT_POSTED" = "true" ] && { [ "$UNRESOLVED" -gt 0 ] || [ "$CI_RED" -gt 0 ]; }; then
  VERDICT="ESCALATE"
else
  VERDICT="WAIT"
fi

jq -n \
  --arg pr "$PR" --arg bot "$BOT" --arg head "$HEAD_SHA" --arg verdict "$VERDICT" \
  --argjson bot_posted "$BOT_POSTED" --argjson ready "$READY" \
  --argjson unresolved "$UNRESOLVED" --argjson red "$CI_RED" --argjson pending "$CI_PENDING" \
  --argjson ci "$(jq '.ci' <<<"$CHECKS")" \
  '{
    pr: $pr, bot: $bot, bot_posted: $bot_posted, ready: $ready,
    unresolved_threads: $unresolved,
    ci: ($ci + {red: $red, pending: $pending}),
    head_sha: $head, verdict: $verdict
  }'

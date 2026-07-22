#!/usr/bin/env bash
# request-and-poll-bot.sh <owner/repo> <PR#> <copilot|coderabbit> [timeout_secs]
# Request an external PR bot review (Copilot: POST; CodeRabbit: auto on open),
# poll until its review lands or timeout, then emit {reviews, comments} JSON.
# Shared: drive-to-mergeable step 3, mergeable-loop, deep-audit.
# Exit 0 + JSON on success; exit 1 on timeout (partial JSON to stderr note).
set -euo pipefail

REPO="${1:?usage: request-and-poll-bot.sh <owner/repo> <PR#> <copilot|coderabbit> [timeout]}"
PR="${2:?missing PR#}"
BOT="${3:?missing bot: copilot|coderabbit}"
TIMEOUT="${4:-300}"
INTERVAL=15

case "$BOT" in
  copilot)
    MATCH="copilot"
    # Request Copilot — idempotent-ish; ignore "already requested" noise.
    gh api "repos/$REPO/pulls/$PR/requested_reviewers" -X POST \
      -f "reviewers[]=copilot-pull-request-reviewer[bot]" >/dev/null 2>&1 || true
    ;;
  coderabbit)
    MATCH="coderabbit"
    # CodeRabbit auto-reviews on PR open — no request call.
    ;;
  *) echo "unknown bot: $BOT (want copilot|coderabbit)" >&2; exit 1 ;;
esac

elapsed=0
while [ "$elapsed" -lt "$TIMEOUT" ]; do
  REVIEWS=$(gh pr view "$PR" --repo "$REPO" --json reviews \
    --jq "[.reviews[] | select(.author.login | ascii_downcase | contains(\"$MATCH\"))]" 2>/dev/null || echo '[]')
  if [ "$(jq 'length' <<<"$REVIEWS")" -gt 0 ]; then
    COMMENTS=$(gh api "repos/$REPO/pulls/$PR/comments" --paginate 2>/dev/null || echo '[]')
    jq -n --argjson reviews "$REVIEWS" --argjson comments "$COMMENTS" \
      '{bot: "'"$BOT"'", reviews: $reviews, comments: $comments}'
    exit 0
  fi
  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))
done

echo "timeout: no $BOT review after ${TIMEOUT}s" >&2
exit 1

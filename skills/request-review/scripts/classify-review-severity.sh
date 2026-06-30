#!/usr/bin/env bash
# classify-review-severity.sh
#
# Pluggable severity classifier for automated PR review bots. Reads one
# review-comment body on stdin, emits the raw severity token only. Callers
# keep their OWN action policy (fix/maybe/skip vs block/skip) — this script
# normalizes the marker, it does not decide action.
#
# ADAPTERS select a bot's marker vocabulary. CodeRabbit is the reference
# adapter (richest badge set). `generic` matches plain-English severity words
# and works for most bots + human reviewers. Add a bot = add a MARKERS_<bot>
# table + a case branch; the output contract stays fixed so every caller keeps
# working.
#
# Output: JSON {severity, marker, bot} where
#   severity ∈ critical|major|minor|nit|refactor|verification|unknown
#   marker   = the literal token matched (or "" on fallback)
#   bot      = the adapter used
# Used by: address-bot-review (step 2), request-review (step 3b).
#
# Usage: echo "$body" | classify-review-severity.sh [--bot coderabbit|generic]
#   default bot = coderabbit (override via --bot or REVIEW_BOT env)
#
# Fail-safe: no recognized marker → "unknown". Callers that must not
# under-react (request-review) treat unknown-but-actionable as major; callers
# that skip nits by default (address-bot-review) treat unknown as skip. That
# policy split stays in the skills, not here.
set -euo pipefail

BOT="${REVIEW_BOT:-coderabbit}"
while [ $# -gt 0 ]; do
  case "$1" in
    --bot) BOT="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

BODY="$(cat)"

# Each table: ordered by precedence (highest severity wins on multi-match).
# Entry format: severity|marker
MARKERS_coderabbit='
critical|🔴 Critical
critical|⚠️ Critical
critical|**Critical:**
critical|_⚠️ Potential issue_
critical|⚠️ Potential issue
major|🟠 Major
minor|🟡 Minor
minor|**Minor:**
refactor|🛠️ Refactor suggestion
refactor|🛠️ Refactor
nit|🧹 Nitpick
nit|**Nitpick:**
verification|🧠 Verification
verification|❓ Verification
'

# Plain-English fallback — matched case-insensitively. Works for any bot or
# human reviewer that labels severity in words. Substring match, so keep the
# precedence order (critical first) to win ties.
MARKERS_generic='
critical|blocker
critical|critical
major|major
minor|minor
refactor|refactor
nit|nitpick
nit|nit:
verification|verification
'

case "$BOT" in
  coderabbit) MARKERS="$MARKERS_coderabbit"; GREP_FLAGS="-qF" ;;
  generic)    MARKERS="$MARKERS_generic";    GREP_FLAGS="-qiF" ;;
  *) echo "classify-review-severity: unknown bot '$BOT' (try: coderabbit|generic)" >&2; exit 2 ;;
esac

while IFS='|' read -r sev marker; do
  [ -z "$sev" ] && continue
  if printf '%s' "$BODY" | grep $GREP_FLAGS -- "$marker"; then
    jq -n --arg severity "$sev" --arg marker "$marker" --arg bot "$BOT" \
      '{severity: $severity, marker: $marker, bot: $bot}'
    exit 0
  fi
done <<EOF
$MARKERS
EOF

jq -n --arg bot "$BOT" '{severity: "unknown", marker: "", bot: $bot}'

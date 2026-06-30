#!/usr/bin/env bash
# catch-up-decide.sh <target-ref>
#
# Pure count-based merge/rebase decision. Skill body still applies the
# "PR already has reviews → prefer merge" override after reading this.
#
# Output: JSON {target, to_absorb, ours, choice, reason}
# Used by: catch-up-main.
set -euo pipefail

TARGET="${1:?usage: catch-up-decide.sh <target-ref>}"

# Strip origin/ if user passed it already
REMOTE_REF="$TARGET"
[[ "$TARGET" != origin/* ]] && REMOTE_REF="origin/$TARGET"

git fetch -q origin "${TARGET#origin/}" 2>/dev/null || true

TO_ABSORB=$(git log --oneline "HEAD..$REMOTE_REF" 2>/dev/null | wc -l | tr -d ' ')
OURS=$(git log --oneline "$REMOTE_REF..HEAD" 2>/dev/null | wc -l | tr -d ' ')

if [ "$OURS" -gt 10 ]; then
  CHOICE="merge"; REASON="ours>10 — rebase replay too painful"
elif [ "$OURS" -le 5 ] && [ "$TO_ABSORB" -le 10 ]; then
  CHOICE="rebase"; REASON="small branch + small drift — keep history linear"
else
  CHOICE="merge"; REASON="default — merge preserves SHAs"
fi

jq -n \
  --arg target "$REMOTE_REF" \
  --argjson to_absorb "$TO_ABSORB" \
  --argjson ours "$OURS" \
  --arg choice "$CHOICE" \
  --arg reason "$REASON" \
  '{target: $target, to_absorb: $to_absorb, ours: $ours, choice: $choice, reason: $reason,
    note: "Override to merge if PR has reviews/comments (preserve SHAs)."}'

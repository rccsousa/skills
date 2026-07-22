#!/usr/bin/env bash
# classify-coderabbit-severity.sh
#
# Pure marker → severity classifier for a single CodeRabbit comment body.
# Reads the comment body on stdin, emits the raw severity token only.
# Each skill keeps its OWN action policy (fix/maybe/skip vs block/skip) —
# this script does NOT decide action, only normalizes the marker.
#
# Single source of truth for CR severity markers. If CodeRabbit changes
# its badges, update the MARKERS table here and both skills follow.
#
# Output: JSON {severity, marker} where
#   severity ∈ critical|major|minor|nit|refactor|verification|unknown
#   marker   = the literal badge matched (or "" on fallback)
# Used by: address-bot-review (step 2), request-review (step 3b).
#
# Fail-safe: a body with no recognized marker → "unknown". Callers that
# must not under-react (request-review) treat unknown-but-actionable as
# major; callers that skip nits by default (address-bot-review) treat
# unknown as skip. That policy split stays in the skills, not here.
set -euo pipefail

BODY="$(cat)"

# Ordered by precedence: highest severity wins on multi-match.
# Each entry: severity|fixed-string-marker
MARKERS='
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

while IFS='|' read -r sev marker; do
  [ -z "$sev" ] && continue
  if printf '%s' "$BODY" | grep -qF -- "$marker"; then
    jq -n --arg severity "$sev" --arg marker "$marker" \
      '{severity: $severity, marker: $marker}'
    exit 0
  fi
done <<EOF
$MARKERS
EOF

jq -n '{severity: "unknown", marker: ""}'

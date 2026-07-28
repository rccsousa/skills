#!/usr/bin/env bash
# close-card.sh — after a triage issue is filed, link it back on the Basecamp
# card and move the card to the Triaged column.
#
# Usage:
#   close-card.sh <card_id> <issue_url> [--to <column>] \
#                 [--card-table <id>] [--in <project>]
#
#   --to          Triaged/In-progress column (name or id). Omit → comment only.
#   --card-table  table id, if the project has multiple card tables
#   --in          project override (else resolved from .basecamp/config.json)
#
# Always comments the issue URL. Moves only when --to is given; if the move
# fails (no such column, ambiguous table), it keeps the comment and reports
# comment-only rather than erroring — matching "no Triaged column → comment
# only". Emits a machine line:
#   CARD <card_id> <commented|comment-failed> <moved|move-failed|no-move> [detail]
set -euo pipefail

[ "$#" -ge 2 ] || { echo "usage: close-card.sh <card_id> <issue_url> [--to <col>] [--card-table <id>] [--in <project>]" >&2; exit 2; }

card_id="$1"; issue_url="$2"; shift 2
to=""; table=""; project=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --to) to="$2"; shift 2 ;;
    --card-table) table="$2"; shift 2 ;;
    --in) project="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

in_args=(); [ -n "$project" ] && in_args=(--in "$project")

# 1. Comment the filed issue URL back on the card.
if basecamp comment "$card_id" "🔗 Filed: $issue_url" "${in_args[@]}"; then
  commented="commented"
else
  commented="comment-failed"
fi

# 2. Move — only if a target column was given.
if [ -z "$to" ]; then
  echo "CARD $card_id $commented no-move (no --to given)"
  exit 0
fi

move_args=(cards move "$card_id" --to "$to")
[ -n "$table" ] && move_args+=(--card-table "$table")
[ -n "$project" ] && move_args+=(--in "$project")

if basecamp "${move_args[@]}"; then
  echo "CARD $card_id $commented moved (→ $to)"
else
  echo "CARD $card_id $commented move-failed (comment kept; column '$to' unresolved)"
fi

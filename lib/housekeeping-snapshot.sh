#!/usr/bin/env bash
# housekeeping-snapshot.sh
#
# For each non-primary worktree, gather state needed for cleanup decisions.
# Output: JSON [{name, path, branch, lock_state, dirty, unpushed, pr_number, pr_state, pr_merged_at}]
#
# Used by: housekeeping.
set -euo pipefail

# Worktree layout (path/branch/isMain) comes from the shared primitive.
# Non-main entries → cleanup rows; lock/dirty/PR state computed below.
WORKTREES=$(~/.claude/lib/get-worktree-info.sh \
  | jq -r '.worktrees[] | select(.isMain | not) | [.name, .path, .branch] | @tsv')

RESULT="[]"
while IFS=$'\t' read -r name wt branch; do
  [ -z "$wt" ] && continue

  wt_id=$(basename "$(readlink -f "$wt" 2>/dev/null || echo "$wt")")

  # Lock state
  lock_file=".git/worktrees/$wt_id/locked"
  lock_state="unlocked"
  if [ -f "$lock_file" ]; then
    pid=$(grep -oE 'pid [0-9]+' "$lock_file" 2>/dev/null | awk '{print $2}' || true)
    if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
      lock_state="alive:$pid"
    else
      lock_state="dead:${pid:-unknown}"
    fi
  fi

  # Dirty + unpushed (cd into worktree dir for these)
  dirty=0; unpushed=0
  if [ -d "$wt" ]; then
    dirty=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    unpushed=$(git -C "$wt" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
  fi

  # PR state for this branch
  pr_json=$(gh pr list --state all --head "$branch" --json number,state,mergedAt --limit 1 2>/dev/null || echo '[]')
  pr_number=$(jq -r '.[0].number // null' <<<"$pr_json")
  pr_state=$(jq -r '.[0].state // null' <<<"$pr_json")
  pr_merged_at=$(jq -r '.[0].mergedAt // null' <<<"$pr_json")

  # Decide safe-to-auto-remove: lock unlocked/dead AND dirty=0 AND PR MERGED
  safe=false
  if { [ "$lock_state" = "unlocked" ] || [[ "$lock_state" == dead:* ]]; } \
     && [ "$dirty" -eq 0 ] \
     && [ "$pr_state" = "MERGED" ]; then
    safe=true
  fi

  RESULT=$(jq \
    --arg name "$name" --arg path "$wt" --arg branch "$branch" \
    --arg lock "$lock_state" --argjson dirty "$dirty" --argjson unpushed "$unpushed" \
    --argjson pr "$pr_number" --arg prs "$pr_state" --arg prm "$pr_merged_at" \
    --argjson safe "$safe" \
    '. + [{name:$name, path:$path, branch:$branch, lock:$lock,
          dirty:$dirty, unpushed:$unpushed,
          pr_number:$pr, pr_state:(if $prs=="null" then null else $prs end),
          pr_merged_at:(if $prm=="null" then null else $prm end),
          auto_remove_safe:$safe}]' <<<"$RESULT")
done <<<"$WORKTREES"

jq -n --argjson wts "$RESULT" \
  '{count: ($wts|length),
    auto_removable: [$wts[]|select(.auto_remove_safe)],
    needs_decision: [$wts[]|select(.auto_remove_safe|not)],
    all: $wts}'

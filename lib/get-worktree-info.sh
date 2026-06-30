#!/usr/bin/env bash
# get-worktree-info.sh
#
# Parse `git worktree list --porcelain` into normalized JSON. The shared
# primitive for "where is main + what worktrees exist" — the one piece
# housekeeping and sync-worktree-skills both need. Per-worktree cleanup
# state (lock/dirty/unpushed/PR) stays in housekeeping-snapshot.sh; symlink
# math stays in sync-worktree-skills. This script answers only: layout.
#
# Output: JSON
#   {mainPath, worktrees: [{name, path, branch, isMain}]}
#   - mainPath: the primary checkout (git rev-parse --show-toplevel)
#   - branch:   "" for detached HEAD
#   - isMain:   true for the primary worktree
# Used by: housekeeping-snapshot.sh, sync-worktree-skills.
set -euo pipefail

MAIN=$(git rev-parse --show-toplevel)

git worktree list --porcelain | awk -v main="$MAIN" '
  /^worktree / { path=$2; branch=""; next }
  /^branch /   { branch=$2; sub("refs/heads/", "", branch); next }
  /^detached/  { branch=""; next }
  /^$/ { if (path != "") emit() }
  END { if (path != "") emit() }
  function emit() {
    n=split(path, parts, "/"); name=parts[n]
    is_main=(path==main) ? "true" : "false"
    printf "%s\t%s\t%s\t%s\n", name, path, branch, is_main
    path=""
  }
' | jq -R -s '
  {worktrees: [
    split("\n")[] | select(length>0) | split("\t")
    | {name: .[0], path: .[1], branch: .[2], isMain: (.[3]=="true")}
  ]} | .mainPath = ([.worktrees[] | select(.isMain) | .path][0])
'

#!/usr/bin/env bash
# Checks deps, links the launcher onto PATH, optionally adds a project and stores a Linear API key.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/linear-grooming"
CONFIG="$CONFIG_DIR/projects.json"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

missing=()
for c in bun gh jq git; do command -v "$c" >/dev/null || missing+=("$c"); done
if ((${#missing[@]})); then echo "Missing: ${missing[*]}" >&2; exit 1; fi
gh auth status >/dev/null 2>&1 || { echo "Run: gh auth login" >&2; exit 1; }

mkdir -p "$BIN_DIR"
ln -sf "$SKILL_DIR/bin/linear-grooming" "$BIN_DIR/linear-grooming"
chmod +x "$SKILL_DIR/bin/linear-grooming"
echo "Linked $BIN_DIR/linear-grooming"
[[ :$PATH: == *":$BIN_DIR:"* ]] || echo "  note: $BIN_DIR is not on PATH"

ask() { local v; read -r -p "$1${2:+ [$2]}: " v; echo "${v:-$2}"; }

mkdir -p "$CONFIG_DIR"
[[ -f $CONFIG ]] || echo '{}' >"$CONFIG"
if [[ $(ask "Add a project? (y/n)" y) == y ]]; then
  dir=$(ask "Repo directory" "$PWD")
  dir=$(cd "${dir/#\~/$HOME}" && git rev-parse --show-toplevel)
  name=$(ask "Project name" "$(basename "$dir")")
  repo=$(cd "$dir" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  repos=$(ask "GitHub repos (space-separated owner/repo)" "$repo")
  team=$(ask "Linear team name (empty = all teams)" "")
  echo "Status names as they appear in your Linear team:"
  inProgress=$(ask "  In-progress status" "In Progress")
  inReview=$(ask "  In-review status" "In Review")
  done_=$(ask "  Done status" "Done")
  tmp=$(mktemp)
  jq --arg n "$name" --arg d "${dir/#$HOME/\~}" --arg r "$repos" --arg t "$team" \
    --arg p "$inProgress" --arg v "$inReview" --arg x "$done_" \
    '.[$n] = {dir: $d, repos: ($r | split(" ") | map(select(. != ""))),
      team: (if $t == "" then null else $t end),
      statuses: {inProgress: $p, inReview: $v, done: $x}}' "$CONFIG" >"$tmp" && mv "$tmp" "$CONFIG"
  echo "Saved project \"$name\" to $CONFIG"
fi

echo
echo "Linear access: the /linear-grooming skill uses the Linear MCP by default."
echo "An API key enables --api mode (and the no-Claude loop)."
if [[ $(ask "Store a Linear API key now? (y/n)" n) == y ]]; then
  echo "Create one at https://linear.app/settings/account/security"
  read -r -s -p "Key: " key; echo
  if command -v security >/dev/null; then
    security add-generic-password -U -s linear-api-key -a "$USER" -w "$key"
    echo "Stored in macOS keychain (service: linear-api-key)"
  else
    echo "No keychain; add to your shell profile: export LINEAR_API_KEY=<key>"
  fi
fi

echo
echo "Done. Try: /linear-grooming  (in Claude Code)  or  linear-grooming --once"

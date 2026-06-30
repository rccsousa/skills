#!/usr/bin/env bash
# install.sh — symlink these skills + lib into ~/.claude so Claude Code finds them.
#
# Safe to re-run. Existing files are NOT overwritten — conflicts are reported
# and skipped so your own local skills are never clobbered. Remove a conflicting
# target yourself if you want this repo's version.
#
# Usage: ./install.sh            # symlink into ~/.claude
#        CLAUDE_HOME=/path ./install.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CLAUDE_HOME:-$HOME/.claude}"

mkdir -p "$DEST/skills" "$DEST/lib"

link() {  # $1 = source, $2 = target
  local src="$1" tgt="$2"
  if [ -L "$tgt" ]; then
    # already a symlink — refresh if it points elsewhere
    ln -sfn "$src" "$tgt"; echo "  ↻ $tgt"
  elif [ -e "$tgt" ]; then
    echo "  ⚠ skip (exists, not a symlink): $tgt"
  else
    ln -s "$src" "$tgt"; echo "  ✓ $tgt"
  fi
}

echo "→ skills"
for d in "$REPO"/skills/*/; do
  d="${d%/}"
  link "$d" "$DEST/skills/$(basename "$d")"
done

echo "→ lib"
for f in "$REPO"/lib/*; do
  link "$f" "$DEST/lib/$(basename "$f")"
done

echo "→ done. Restart Claude Code or reload skills to pick them up."
echo "  Deps: gh, jq, perl. Optional: context7 MCP (for the context7-mcp skill)."

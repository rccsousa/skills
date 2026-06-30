#!/usr/bin/env bash
# export-public.sh — SEED tool for the public skills repo.
#
# Copies the SHAREABLE subset of ~/.claude/skills + ~/.claude/lib into this
# repo and strips the personal `rtk ` command prefix. This is the MECHANICAL
# pass only. Editorial sanitization (PII scrub, feedback_* inlining, the
# review-bot generalization) lives in this repo's git history, NOT here.
#
# ⚠️  This OVERWRITES skills/ and lib/. Run it to bootstrap, or to re-pull a
#     skill from the live dir — after which you must re-apply sanitization to
#     that skill by hand. It is NOT a lossless two-way sync.
#
# Source of truth = ~/.claude (live, private, full). This repo = sanitized
# public export. The two diverge by design.
set -euo pipefail

SRC="${CLAUDE_HOME:-$HOME/.claude}"
DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- shareable subset --------------------------------------------------------
# EXCLUDED skills (employer-specific, no generic core):
#   catch-up-pr-base, openfx-deposit-e2e, refresh-workspace
# EXCLUDED lib (orphan only excluded skills):
#   openfx-verify-steps.sh, purge-bt-tokens.sh
SKILLS=(
  address-coderabbit audit-skills catch-up-main context7-mcp council-of-agents
  deep-audit dream feature-flow find-skills fix-pr-checks housekeeping
  improve-skill merge-pr pending pr-interview pr-ready red-team-findings
  request-review review-codex-pr surgical-review sync-worktree-skills
  verify-review-findings
)
LIB=(
  catch-up-decide.sh catch-up-shared.md classify-coderabbit-severity.sh
  commit-push-policy.md extract-interview-hunks.sh fetch-review-threads.sh
  get-worktree-info.sh housekeeping-snapshot.sh pr-checks.sh
  review-output-contract.md
)

echo "→ exporting from $SRC"
rm -rf "$DEST/skills" "$DEST/lib"
mkdir -p "$DEST/skills" "$DEST/lib"

for s in "${SKILLS[@]}"; do
  [ -d "$SRC/skills/$s" ] || { echo "  ⚠ missing skill: $s"; continue; }
  cp -R "$SRC/skills/$s" "$DEST/skills/$s"
done

for f in "${LIB[@]}"; do
  [ -f "$SRC/lib/$f" ] || { echo "  ⚠ missing lib: $f"; continue; }
  cp "$SRC/lib/$f" "$DEST/lib/$f"
done

# --- strip personal `rtk ` prefix (hook adds it locally; breaks others) ------
# Every `rtk ` in the subset precedes a real command — safe blanket strip.
# perl (not BSD sed) — macOS sed lacks the \b word boundary.
find "$DEST/skills" "$DEST/lib" -type f \( -name '*.md' -o -name '*.sh' \) \
  -exec perl -i -pe 's/\brtk //g' {} +

echo "→ exported ${#SKILLS[@]} skills, ${#LIB[@]} lib files (rtk stripped)"
echo "→ NEXT: re-apply editorial sanitization to any freshly re-pulled skill"

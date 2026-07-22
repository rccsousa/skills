#!/usr/bin/env bash
# vendor-skills.sh — make each lib-dependent skill self-contained.
#
# This repo is the public snapshot and the source of truth. `npx skills add`
# installs ONE skill folder at a time into .claude/skills/<name>/ and does NOT
# pull a repo-root lib/. So any skill that calls a shared lib/ script would
# dangle when installed standalone.
#
# This pass fans the shared lib/ files OUT into each skill that needs them:
#   lib/<x>.sh  ->  skills/<name>/scripts/<x>.sh      (referenced as scripts/<x>.sh)
#   lib/<x>.md  ->  skills/<name>/references/<x>.md    (referenced as references/<x>.md)
# and rewrites every ~/.claude/lib/<x> reference (in SKILL.md, sibling prompt
# .md files, and inside vendored .md/.sh) to the bundled relative path.
#
# Convention verified against Anthropic Agent-Skills best-practices and real
# npx-skills-distributed skills (mattpocock/skills): bundled scripts/docs are
# referenced by a plain relative path from the skill root (scripts/foo.sh,
# references/foo.md); Claude resolves it against the skill directory. Script-to-
# script calls use $(dirname "$0")/sibling.sh so they resolve regardless of CWD
# or install location.
#
# lib/ stays the single canonical source. The copies under skills/<name>/ are
# GENERATED artifacts — never hand-edit them; edit lib/ and re-run. Idempotent,
# repo-local, deterministic: re-run any time.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# skill -> full dependency closure (transitive deps already expanded).
deps_for() {
  case "$1" in
    address-bot-review)   echo "classify-review-severity.sh fetch-review-threads.sh commit-push-policy.md" ;;
    catch-up-main)        echo "catch-up-shared.md catch-up-decide.sh commit-push-policy.md" ;;
    drive-to-mergeable)   echo "request-and-poll-bot.sh classify-coderabbit-severity.sh resolve-pr-threads.sh commit-push-policy.md" ;;
    feature-flow)         echo "commit-push-policy.md" ;;
    housekeeping)         echo "housekeeping-snapshot.sh get-worktree-info.sh" ;;
    merge-pr)             echo "pr-checks.sh" ;;
    mergeable-loop)       echo "bot-reviewed.sh pr-checks.sh" ;;
    pr-interview)         echo "extract-interview-hunks.sh" ;;
    pr-ready)             echo "fetch-review-threads.sh pr-checks.sh" ;;
    request-review)       echo "classify-review-severity.sh fetch-review-threads.sh" ;;
    review-codex-pr)      echo "review-output-contract.md" ;;
    surgical-review)      echo "review-output-contract.md" ;;
    sync-worktree-skills) echo "get-worktree-info.sh" ;;
    *)                    echo "" ;;
  esac
}

SKILLS_WITH_DEPS=(
  address-bot-review catch-up-main drive-to-mergeable feature-flow housekeeping
  merge-pr mergeable-loop pr-interview pr-ready request-review review-codex-pr
  surgical-review sync-worktree-skills
)

vendor_one() {  # $1 = skill name
  local skill="$1" dst="skills/$1" f src
  [ -d "$dst" ] || { echo "  ✗ missing skill dir: $dst"; return 1; }

  # wipe prior generated artifacts so re-runs are deterministic
  rm -rf "$dst/scripts" "$dst/references"

  for f in $(deps_for "$skill"); do
    src="lib/$f"
    [ -f "$src" ] || { echo "  ✗ missing lib source: $src"; return 1; }
    case "$f" in
      *.sh) mkdir -p "$dst/scripts";    cp "$src" "$dst/scripts/$f";    chmod +x "$dst/scripts/$f" ;;
      *.md) mkdir -p "$dst/references"; cp "$src" "$dst/references/$f" ;;
      *)    echo "  ✗ unhandled dep type: $f"; return 1 ;;
    esac
  done

  # Rewrite Claude-facing refs (run by the model, resolved against skill root):
  #   ~/.claude/lib/<x>.sh -> scripts/<x>.sh ;  ~/.claude/lib/<x>.md -> references/<x>.md
  # Applies to SKILL.md, sibling prompt .md, AND vendored .md (e.g. catch-up-shared.md).
  find "$dst" -type f -name '*.md' -print0 | while IFS= read -r -d '' file; do
    perl -i -pe 's{~/\.claude/lib/([\w.-]+\.sh)}{scripts/$1}g;
                  s{~/\.claude/lib/([\w.-]+\.md)}{references/$1}g' "$file"
  done

  # Rewrite script-to-script calls inside vendored .sh to self-locating paths
  # ("$(dirname "$0")/sibling.sh") — resolves regardless of CWD / install dir.
  if [ -d "$dst/scripts" ]; then
    find "$dst/scripts" -type f -name '*.sh' -print0 | while IFS= read -r -d '' file; do
      perl -i -pe 's{~/\.claude/lib/([\w.-]+\.sh)}{"\$(dirname \"\$0\")/$1"}g' "$file"
    done
  fi

  echo "  ✓ $skill ← [$(deps_for "$skill")]"
}

echo "→ vendoring lib closures into self-contained skill folders"
for s in "${SKILLS_WITH_DEPS[@]}"; do
  vendor_one "$s"
done

# Guard: no ~/.claude/lib/ reference may survive anywhere under skills/.
if grep -rn '~/\.claude/lib/' skills/ >/dev/null 2>&1; then
  echo "✗ FAIL: dangling ~/.claude/lib/ refs remain:" >&2
  grep -rn '~/\.claude/lib/' skills/ >&2
  exit 1
fi

# Guard: every vendored shell script parses.
while IFS= read -r -d '' f; do
  bash -n "$f" || { echo "✗ FAIL: syntax error in $f" >&2; exit 1; }
done < <(find skills -path '*/scripts/*.sh' -type f -print0)

echo "→ done. Each lib-dependent skill is now self-contained (scripts/ + references/)."

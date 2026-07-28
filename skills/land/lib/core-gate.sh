#!/usr/bin/env bash
# Core gate for /land. Exit 0 = safe to auto-merge, 1 = refuse, 2 = usage/lookup error.
# Usage: core-gate.sh <PR#> [repo-root]
set -uo pipefail

PR="${1:-}"
ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$PR" ] || { echo "usage: core-gate.sh <PR#> [repo-root]" >&2; exit 2; }
[ -n "$ROOT" ] || { echo "not a git repo" >&2; exit 2; }

CONFIG="$ROOT/.nightshift/config.json"

UNIVERSAL_DENIES=(
  '*/migrations/*' 'db/schema.*' '*/schema.rb' 'priv/repo/migrations/*'
  '.github/*' 'Dockerfile*' 'docker-compose*' 'fly.toml' '*.tf' '*.tfvars'
  'package-lock.json' 'yarn.lock' 'pnpm-lock.yaml' 'mix.lock' 'Gemfile.lock'
  'go.sum' 'Cargo.lock'
  '*/auth/*' '*/permissions/*' '*polic*' '*authoriz*'
  '.env*' '*secrets*' '*credential*'
  'CODEOWNERS' 'CLAUDE.md' 'AGENTS.md' '.claude/*'
)

REPO_DENIES=()
if [ -f "$CONFIG" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] && REPO_DENIES+=("$p")
  done < <(jq -r '.core_paths // [] | .[]' "$CONFIG" 2>/dev/null)
else
  echo "note: no $CONFIG — universal denies only" >&2
fi

FILES="$(gh pr view "$PR" --json files --jq '.files[].path' 2>/dev/null)"
if [ -z "$FILES" ]; then
  echo "could not read changed files for PR #$PR" >&2
  exit 2
fi

# Glob semantics: `**/x/**` in config is normalised to `*/x/*` so bash `case`
# matching works without extglob/globstar.
normalise() { printf '%s' "${1//\*\*/\*}"; }

hits=()
while IFS= read -r f; do
  for pat in "${UNIVERSAL_DENIES[@]}" ${REPO_DENIES+"${REPO_DENIES[@]}"}; do
    n="$(normalise "$pat")"
    # shellcheck disable=SC2254
    case "$f" in
      $n)   hits+=("$f  ($pat)"); break ;;
      */$n) hits+=("$f  ($pat)"); break ;;
    esac
  done
done <<< "$FILES"

if [ ${#hits[@]} -gt 0 ]; then
  echo "CORE-GATE FAIL #$PR"
  printf '  %s\n' "${hits[@]}"
  exit 1
fi

echo "CORE-GATE PASS #$PR"
exit 0

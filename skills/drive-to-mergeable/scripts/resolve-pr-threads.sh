#!/usr/bin/env bash
# resolve-pr-threads.sh <owner/repo> <PR#> [--dry-run]
# Resolve every unresolved review thread on a PR (Copilot/CodeRabbit/human alike).
# MUTATION: fires resolveReviewThread per unresolved thread. Callers are gated
# skills (drive-to-mergeable step 6, deep-audit). --dry-run lists, resolves nothing.
# Shared. Prints "resolved N of M" to stderr, {resolved, total} JSON to stdout.
set -euo pipefail

REPO="${1:?usage: resolve-pr-threads.sh <owner/repo> <PR#> [--dry-run]}"
PR="${2:?missing PR#}"
DRY="${3:-}"
OWNER="${REPO%/*}"; NAME="${REPO#*/}"

THREADS=$(gh api graphql -f owner="$OWNER" -f name="$NAME" -F number="$PR" -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) { nodes { id isResolved } }
      }
    }
  }' --jq '.data.repository.pullRequest.reviewThreads.nodes')

TOTAL=$(jq 'length' <<<"$THREADS")
UNRESOLVED_IDS=$(jq -r '.[] | select(.isResolved==false) | .id' <<<"$THREADS")

n=0
for id in $UNRESOLVED_IDS; do
  if [ "$DRY" = "--dry-run" ]; then
    echo "would resolve: $id" >&2
  else
    gh api graphql -f threadId="$id" -f query='
      mutation($threadId: ID!) {
        resolveReviewThread(input: {threadId: $threadId}) {
          thread { isResolved }
        }
      }' >/dev/null
  fi
  n=$((n + 1))
done

echo "resolved $n of $TOTAL threads${DRY:+ (dry-run)}" >&2
jq -n --argjson resolved "$n" --argjson total "$TOTAL" '{resolved: $resolved, total: $total}'

#!/usr/bin/env bash
# pr-checks.sh <PR#>
# Output: JSON readiness report. Exit 0 always; caller reads JSON.
# Shared across skills: pr-ready, feature-flow (pre-PR gate), surgical-review.
set -euo pipefail

PR="${1:?usage: pr-checks.sh <PR#>}"

# Single gh call for static fields.
META=$(gh pr view "$PR" --json baseRefName,mergeStateStatus,reviewDecision,isDraft,title,additions,deletions,commits)

BASE=$(jq -r '.baseRefName' <<<"$META")
MERGE_STATE=$(jq -r '.mergeStateStatus' <<<"$META")
REVIEW_DECISION=$(jq -r '.reviewDecision // "NONE"' <<<"$META")
IS_DRAFT=$(jq '.isDraft' <<<"$META")
TITLE=$(jq -r '.title' <<<"$META")
ADDS=$(jq '.additions' <<<"$META")
DELS=$(jq '.deletions' <<<"$META")
COMMIT_COUNT=$(jq '.commits | length' <<<"$META")

# reviewThreads only available via GraphQL.
REPO=$(gh repo view --json owner,name -q '.owner.login + "/" + .name')
OWNER="${REPO%/*}"; NAME="${REPO#*/}"
UNRESOLVED=$(gh api graphql -f owner="$OWNER" -f name="$NAME" -F number="$PR" -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) { nodes { isResolved } }
      }
    }
  }' --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved==false)]|length')

# CI: any non-pass row = fail. Empty = fail (no checks configured).
CHECKS_JSON=$(gh pr checks "$PR" --json bucket,name,state 2>/dev/null || echo '[]')
CI_FAIL_COUNT=$(jq '[.[] | select(.bucket != "pass")] | length' <<<"$CHECKS_JSON")
CI_TOTAL=$(jq 'length' <<<"$CHECKS_JSON")
CI_OK=$([ "$CI_FAIL_COUNT" -eq 0 ] && [ "$CI_TOTAL" -gt 0 ] && echo true || echo false)

# Size: adds+dels vs 1k threshold (warn-only per PR hygiene).
SIZE=$((ADDS + DELS))
SIZE_OK=$([ "$SIZE" -lt 1000 ] && echo true || echo false)

# Commit messages — conventional commit regex.
# Pull subjects from PR metadata (canonical source), skip merge commits (>1 parent).
BAD_COMMITS=$(jq -r '.commits[].messageHeadline' <<<"$META" \
  | grep -v '^Merge ' \
  | grep -cvE '^(feat|fix|chore|refactor|test|docs|perf|build|ci|style|revert)(\(.+\))?: .+' || true)
COMMITS_OK=$([ "$BAD_COMMITS" -eq 0 ] && echo true || echo false)

MERGE_OK=$([ "$MERGE_STATE" = "CLEAN" ] && echo true || echo false)
REVIEW_OK=$([ "$REVIEW_DECISION" = "APPROVED" ] && [ "$UNRESOLVED" -eq 0 ] && echo true || echo false)
NOT_DRAFT=$([ "$IS_DRAFT" = "false" ] && echo true || echo false)

READY=$([ "$CI_OK" = "true" ] && [ "$MERGE_OK" = "true" ] && [ "$REVIEW_OK" = "true" ] \
        && [ "$NOT_DRAFT" = "true" ] && [ "$COMMITS_OK" = "true" ] && echo true || echo false)

jq -n \
  --arg pr "$PR" --arg title "$TITLE" --arg base "$BASE" \
  --argjson adds "$ADDS" --argjson dels "$DELS" --argjson commits "$COMMIT_COUNT" \
  --argjson ci "$CI_OK" --argjson ci_fail "$CI_FAIL_COUNT" --argjson ci_total "$CI_TOTAL" \
  --arg merge_state "$MERGE_STATE" --argjson merge "$MERGE_OK" \
  --arg review_decision "$REVIEW_DECISION" --argjson unresolved "$UNRESOLVED" --argjson review "$REVIEW_OK" \
  --argjson size "$SIZE" --argjson size_ok "$SIZE_OK" \
  --argjson bad_commits "$BAD_COMMITS" --argjson commits_ok "$COMMITS_OK" \
  --argjson draft "$IS_DRAFT" --argjson not_draft "$NOT_DRAFT" \
  --argjson ready "$READY" \
  '{
    pr: $pr, title: $title, base: $base,
    diff: {additions: $adds, deletions: $dels, commits: $commits},
    ci: {ok: $ci, failing: $ci_fail, total: $ci_total},
    merge: {ok: $merge, state: $merge_state},
    review: {ok: $review, decision: $review_decision, unresolved_threads: $unresolved},
    size: {ok: $size_ok, loc: $size, threshold: 1000},
    commits: {ok: $commits_ok, non_conventional: $bad_commits},
    draft: {ok: $not_draft, is_draft: $draft},
    ready: $ready
  }'

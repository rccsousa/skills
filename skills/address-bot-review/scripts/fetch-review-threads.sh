#!/usr/bin/env bash
# fetch-review-threads.sh <pr-number>
#
# Single GraphQL fetch of a PR's reviews + review threads, normalized to a
# superset JSON shape so every consumer skill reads the fields it needs.
# Owner/repo auto-detected from the current repo (respects forks: the PR
# and its threads live in the BASE repo, which `gh repo view` resolves).
#
# Output: JSON
#   {
#     reviews: [{author, state, submittedAt, body}],
#     threads: [{id, isResolved, isOutdated, path, line,
#                comments: [{databaseId, body, author, createdAt}]}]
#   }
# Consumers:
#   - pr-ready          (threads → unresolved detail; path/line)
#   - request-review    (reviews → "has CR reviewed?"; threads → severity)
#   - address-bot-review(threads → id for resolve, databaseId for reply)
#
# Note: returns ALL threads/reviews regardless of author. Caller filters to
# CodeRabbit (author == coderabbitai[bot]) and applies isResolved/isOutdated
# policy — that judgement stays in the skill.
set -euo pipefail

PR="${1:?usage: fetch-review-threads.sh <pr-number>}"

read -r OWNER NAME < <(gh repo view --json owner,name \
  -q '.owner.login + " " + .name')

gh api graphql \
  -f owner="$OWNER" -f name="$NAME" -F number="$PR" \
  -f query='
    query($owner:String!,$name:String!,$number:Int!){
      repository(owner:$owner,name:$name){
        pullRequest(number:$number){
          reviews(first:50){nodes{author{login} state submittedAt body}}
          reviewThreads(first:100){nodes{
            id isResolved isOutdated path line
            comments(first:10){nodes{databaseId body author{login} createdAt}}
          }}
        }
      }
    }' \
  --jq '{
    reviews: [.data.repository.pullRequest.reviews.nodes[]
      | {author: .author.login, state, submittedAt, body}],
    threads: [.data.repository.pullRequest.reviewThreads.nodes[]
      | {id, isResolved, isOutdated, path, line,
         comments: [.comments.nodes[]
           | {databaseId, body, author: .author.login, createdAt}]}]
  }'

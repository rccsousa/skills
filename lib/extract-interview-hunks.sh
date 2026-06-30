#!/usr/bin/env bash
# extract-interview-hunks.sh
#
# Reads a unified diff on stdin, emits per-hunk stats + risk-keyword hits.
# Deterministic part of pr-interview step 2 only: parse hunks, count LOC,
# scan keyword families. The SELECTION (1 largest + 2 risk, distinct files,
# skip-if-same) stays in the skill — that's the judgement call.
#
# Output: JSON [{file, hunk, adds, dels, churn, keywords:[family,...]}]
#   sorted by churn desc. `keywords` = risk families whose regex hit the
#   hunk body. Skill picks the largest-churn hunk + top keyword-dense hunks.
# Used by: pr-interview.
#
# Usage: gh pr diff <n> | extract-interview-hunks.sh
#        git diff origin/<base>..HEAD | extract-interview-hunks.sh
set -euo pipefail

awk '
  function flush(  fam) {
    if (file == "" || hunk == "") return
    kw = ""
    for (fam in hit) if (hit[fam]) kw = kw (kw=="" ? "" : ",") fam
    printf "%s\t%s\t%d\t%d\t%s\n", file, hunk, adds, dels, kw
  }
  function reset(  fam) { adds=0; dels=0; for (fam in hit) hit[fam]=0 }

  /^\+\+\+ b\// { flush(); file=substr($0,7); hunk=""; reset(); next }
  /^@@ /        { flush(); hunk=$0; sub(/ @@.*/, " @@", hunk); reset(); next }
  /^\+\+\+/ || /^---/ { next }

  /^[+-]/ {
    if (hunk=="") next
    line = tolower($0)
    if (substr($0,1,1)=="+") adds++; else dels++
    if (line ~ /auth|token|jwt|session|secret|credential/)        hit["auth"]=1
    if (line ~ /amount|balance|transfer|currency|money|cents/)    hit["money"]=1
    if (line ~ /webhook|signature|hmac|hash/)                     hit["webhook"]=1
    if (line ~ /migration|alter table|drop|create table/)         hit["migration"]=1
    if (line ~ /retry|backoff|timeout|race|lock/)                 hit["retry"]=1
    if (line ~ /throw|catch|fail|error|log\.(error|warn)/)        hit["error"]=1
    if (line ~ /cache|ttl|invalidate|stale/)                      hit["cache"]=1
  }
  END { flush() }
' | jq -R -s '
  [ split("\n")[] | select(length>0) | split("\t")
    | {file: .[0], hunk: .[1], adds: (.[2]|tonumber), dels: (.[3]|tonumber),
       churn: ((.[2]|tonumber) + (.[3]|tonumber)),
       keywords: (if .[4]=="" then [] else (.[4]|split(",")) end)} ]
  | sort_by(-.churn)
'

#!/bin/sh

deny() {
  if command -v jq >/dev/null 2>&1; then
    reason=$(printf '%s' "$1" | jq -Rs .)
  else
    reason='"Blocked by env-file-guard.sh: env files may hold live credentials."'
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$reason"
  exit 0
}

REASON='Blocked: .env*/.envrc may hold live credentials. Only .env.example is permitted. If you need a value from one, ask the user for it.'

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s' "$input" | grep -q '\.env' &&
    deny 'Blocked: jq unavailable, so this guard cannot inspect the call and fails closed.'
  exit 0
fi

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
payload=$(printf '%s' "$input" | jq -r '.tool_input | if type=="string" then . else tojson end' 2>/dev/null)
[ -n "$payload" ] || exit 0

strip_example() { sed -E 's/\.env\.example($|[^.[:alnum:]_-])/\1/g'; }

case "$tool" in
  apply_patch)
    paths=$(printf '%s' "$payload" | grep -Eo '\*\*\* (Add|Update|Delete) File: [^\\"]*|\*\*\* Move to: [^\\"]*')
    printf '%s' "$paths" | strip_example | grep -q '\.env' && deny "$REASON"
    ;;
  *)
    printf '%s' "$payload" | strip_example | grep -q '\.env' && deny "$REASON"
    ;;
esac
exit 0

#!/usr/bin/env bash
# Global mutex for nightshift. `mkdir` is the atomic primitive — macOS has no flock.
# Usage: nightshift-lock.sh acquire <lockdir> [ttl_s] [max_wait_s]
#        nightshift-lock.sh release <lockdir>
set -uo pipefail

ACTION="${1:-}"
LOCK="${2:-}"
TTL="${3:-1200}"       # stale after 20m — a dead session must not deadlock the run
MAX_WAIT="${4:-2400}"

[ -n "$ACTION" ] && [ -n "$LOCK" ] || {
  echo "usage: nightshift-lock.sh acquire|release <lockdir> [ttl] [max_wait]" >&2; exit 2; }

mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

case "$ACTION" in
  acquire)
    waited=0
    while ! mkdir "$LOCK" 2>/dev/null; do
      if [ -d "$LOCK" ]; then
        m="$(mtime "$LOCK")"
        if [ -n "$m" ] && [ $(( $(date +%s) - m )) -gt "$TTL" ]; then
          echo "nightshift-lock: reaping stale lock $LOCK" >&2
          rm -rf "$LOCK"
          continue
        fi
      fi
      sleep 5
      waited=$(( waited + 5 ))
      if [ "$waited" -ge "$MAX_WAIT" ]; then
        echo "nightshift-lock: timeout after ${waited}s waiting for $LOCK" >&2
        exit 1
      fi
    done
    echo "$$" > "$LOCK/pid"
    ;;
  release)
    rm -rf "$LOCK"
    ;;
  *)
    echo "unknown action: $ACTION" >&2; exit 2 ;;
esac

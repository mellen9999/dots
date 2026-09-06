#!/bin/sh
# nudge to /compact when a session's context crosses 700k (1M window), then once per 100k band.
# reads Stop-hook json on stdin; estimates context from the last usage entry.
INPUT=$(cat)
T=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
[ -n "$T" ] && [ -f "$T" ] || exit 0

TOK=$(grep '"input_tokens"' "$T" | tail -1 | jq -r '
  (.message.usage // .usage // {}) as $u
  | (($u.input_tokens // 0) + ($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0))' 2>/dev/null)
case "$TOK" in ''|*[!0-9]*) exit 0 ;; esac
[ "$TOK" -gt 700000 ] || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "x"')
STATE="/tmp/claude-ctx-nudge-$SID"
BUCKET=$((TOK / 100000))
LAST=$(cat "$STATE" 2>/dev/null || echo 0)
if [ "$BUCKET" -gt "$LAST" ]; then
  printf '%s' "$BUCKET" > "$STATE"
  K=$((TOK / 1000))
  notify-send -u normal -t 6000 "claude context" "${K}k tokens — /compact to cut cost" 2>/dev/null
fi
exit 0

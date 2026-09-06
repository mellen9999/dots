#!/bin/sh
# faults — tests the tester. injects one known breakage at a time into a sandbox
# copy of the config and asserts run.sh reports THAT check as failed.
#
# a check that cannot fail is decoration, and decoration is exactly how two dead
# hooks survived for months. run this after adding or editing any check.

CD=${CLAUDE_DIR:-$HOME/.claude}
SELF=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT INT TERM
NPROVEN=0 NBLIND=0

seed() {
  rm -rf "$T/cd"; mkdir -p "$T/cd/projects/t/memory"
  cp -rL "$CD/settings.json" "$CD/hooks" "$CD/agents" "$CD/skills" \
         "$CD/statusline-command.sh" "$T/cd/" 2>/dev/null
  printf '# Memory\n' > "$T/cd/projects/t/memory/MEMORY.md"
}

sethook() { # matcher, new command
  jq --arg m "$1" --arg c "$2" \
    '.hooks.PreToolUse |= map(if .matcher == $m then .hooks[0].command = $c else . end)' \
    settings.json > s && mv s settings.json
}

mutate() {
  case $1 in
    phantom-env)  sethook 'Write|Edit' 'echo $CLAUDE_TOOL_INPUT' ;;
    missing-bin)  jq '.hooks.Stop[0].hooks[0].command = "/home/nobody/.local/bin/gone x"' settings.json > s && mv s settings.json ;;
    no-backup)    sethook 'Write|Edit' 'true' ;;
    no-guard)     sethook 'Bash' 'true' ;;
    bad-json)     printf '{oops' > settings.json ;;
    nudge-thresh) sed -i 's/-gt [0-9]*/-gt 999999999/' hooks/context-nudge.sh ;;
    no-statusline) rm -f statusline-command.sh ;;
    agent-nomodel) sed -i '/^model:/d' agents/lookup.md ;;
    skill-nodesc) sed -i '/^description:/d' skills/cpd/SKILL.md ;;
    dangling-link) ln -s /nonexistent/path danglingref ;;
    dead-memory)  printf -- '- [gone](nope.md) — deleted\n' >> projects/t/memory/MEMORY.md ;;
    dead-mcp)     printf '{"mcpServers":{}}' > mcp.json ;;
    dark-memory)  printf 'x\n' > projects/t/memory/unlinked_note.md ;;
    loose-creds)  printf '{}' > .credentials.json; chmod 644 .credentials.json ;;
  esac
}

run() { # fault, check that must go red
  seed
  ( cd "$T/cd" && mutate "$1" ) >/dev/null 2>&1
  if CLAUDE_DIR="$T/cd" sh "$SELF/run.sh" 2>&1 | grep -qE "^(FAIL|warn)  $2"; then
    NPROVEN=$((NPROVEN+1)); printf 'ok     %-15s → %s fires\n' "$1" "$2"
  else
    NBLIND=$((NBLIND+1)); printf 'BLIND  %-15s → %s stayed green\n' "$1" "$2"
  fi
}

run phantom-env    hook-stdin
run missing-bin    hook-bins
run no-backup      hook-backup
run no-guard       hook-guard
run bad-json       settings-json
run nudge-thresh   context-nudge
run no-statusline  statusline
run agent-nomodel  agents
run skill-nodesc   skills
run dangling-link  symlinks
run dead-memory    memory-index
run dead-mcp       mcp-deadconfig
run dark-memory    memory-dark
run loose-creds    credentials

printf '\n%d checks proven, %d blind\n' "$NPROVEN" "$NBLIND"
[ "$NBLIND" = 0 ]

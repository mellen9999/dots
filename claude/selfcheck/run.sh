#!/bin/sh
# selfcheck — proves the claude setup actually works, instead of assuming it.
#
# every hook is EXECUTED with a synthetic payload in a sandbox and asserted on
# its side effect. a hook that silently no-ops is byte-identical to one that
# works until you make it prove itself: two of them were dead for months.
#
#   -q   print failures only
# exit 0 = green, 1 = something is broken.

CD=${CLAUDE_DIR:-$HOME/.claude}
QUIET=0
[ "$1" = "-q" ] && QUIET=1
NPASS=0 NFAIL=0 NWARN=0

ok()   { NPASS=$((NPASS+1)); [ "$QUIET" = 1 ] || printf 'ok    %s\n' "$1"; }
bad()  { NFAIL=$((NFAIL+1)); printf 'FAIL  %s — %s\n' "$1" "$2"; }
warn() { NWARN=$((NWARN+1)); printf 'warn  %s — %s\n' "$1" "$2"; }

command -v jq >/dev/null || { echo 'FAIL  deps — jq missing'; exit 1; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/bin" "$T/home/.claude"
# hooks referenced as ~/.claude/hooks/x must resolve under the sandbox HOME
ln -s "$CD/hooks" "$T/home/.claude/hooks" 2>/dev/null

# stub every side-effecting binary so a check run never beeps, notifies,
# or moves real hq state. calls are logged so we can assert on them.
for b in notify-send paplay logger hq-status wl-copy; do
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/calls.%s"\nexit 0\n' "$T" "$b" > "$T/bin/$b"
  chmod +x "$T/bin/$b"
done
PATH="$T/bin:$PATH"; export PATH

S="$CD/settings.json"

# tab-separated "matcher<TAB>command" for one hook event
hookcmds() {
  jq -r --arg e "$1" '
    .hooks[$e][]? | (.matcher // "") as $m
    | .hooks[]? | select(.type == "command") | $m + "\t" + .command' "$S" 2>/dev/null
}
allcmds() { jq -r '[(.hooks | .. | .command?), .statusLine.command?] | .[] | select(. != null)' "$S" 2>/dev/null; }

# --- settings ---------------------------------------------------------------
if jq -e . "$S" >/dev/null 2>&1; then ok settings-json; else bad settings-json 'not valid json'; fi

# regression guard for the exact bug that motivated this script: hooks reading
# env vars claude code does not set. the payload arrives on stdin.
PHANTOM=$(allcmds | grep -oE 'CLAUDE_(TOOL_INPUT|HOOK_INPUT|TOOL_NAME|TOOL_OUTPUT|FILE_PATH|TOOL_RESPONSE)' | sort -u | tr '\n' ' ')
[ -z "$PHANTOM" ] && ok hook-stdin || bad hook-stdin "reads env claude never sets: ${PHANTOM}(payload is on stdin)"

# every binary a hook shells out to must exist on THIS machine
MISS=
for b in jq git bun tmux notify-send paplay; do command -v "$b" >/dev/null 2>&1 || MISS="$MISS $b"; done
for f in $(allcmds | grep -oE '(~|\$HOME|/home/[a-z][a-z0-9_-]*)[A-Za-z0-9._/-]*/(bin|hooks)/[A-Za-z0-9._-]+' | sort -u); do
  r=$(printf '%s' "$f" | sed "s|^~|$HOME|; s|^\\\$HOME|$HOME|")
  [ -x "$r" ] || MISS="$MISS $f"
done
[ -z "$MISS" ] && ok hook-bins || bad hook-bins "missing:$MISS"

# --- pretooluse: file backup ------------------------------------------------
BK=$(hookcmds PreToolUse | grep -E '^Write\|Edit	' | cut -f2-)
if [ -z "$BK" ]; then
  bad hook-backup 'no Write|Edit PreToolUse hook'
else
  echo original > "$T/target.txt"
  jq -n --arg f "$T/target.txt" '{hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$f}}' \
    | HOME="$T/home" sh -c "$BK" >/dev/null 2>&1
  B=$(find "$T/home" -name 'target.txt.*.bak' 2>/dev/null | head -1)
  if [ -n "$B" ] && [ "$(cat "$B")" = original ]; then ok hook-backup
  else bad hook-backup 'ran but produced no backup — edits are unrecoverable'; fi
fi

# --- pretooluse: destructive command guard ----------------------------------
GD=$(hookcmds PreToolUse | grep -E '^Bash	' | cut -f2-)
if [ -z "$GD" ]; then
  bad hook-guard 'no Bash PreToolUse guard'
else
  GBAD=
  gt() { # want cmd
    r=block
    jq -n --arg c "$2" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}' \
      | sh -c "$GD" >/dev/null 2>&1 && r=allow
    [ "$r" = "$1" ] || GBAD="$GBAD {$2 => $r}"
  }
  gt block "$(printf 'rm -rf /')"
  gt block "$(printf 'rm -rf ~')"
  gt block "$(printf 'sudo rm -fr /*')"
  gt block "$(printf 'cd /tmp && rm -rf $HOME')"
  gt block "$(printf 'mkfs.ext4 /dev/sda')"
  gt block "$(printf 'dd if=/dev/zero of=/dev/sda')"
  gt allow "$(printf 'rm -rf ~/.cache/paru/clone/*')"
  gt allow "$(printf 'rm -rf node_modules')"
  gt allow "$(printf 'git rm -rf src/')"
  gt allow "$(printf 'echo "rm -rf /" > note.txt')"
  gt allow "$(printf 'grep -rn foo /')"
  gt allow "$(printf 'ls -la /')"
  [ -z "$GBAD" ] && ok hook-guard || bad hook-guard "wrong verdicts:$GBAD"
fi

# --- stop / sessionstart / precompact hooks ---------------------------------
printf '{"message":{"usage":{"input_tokens":800,"cache_read_input_tokens":1200}}}\n' > "$T/low.jsonl"
printf '{"message":{"usage":{"input_tokens":400000,"cache_read_input_tokens":500000}}}\n' > "$T/high.jsonl"

runhooks() { # event, extra-json
  ev=$1; extra=$2; fails=
  hookcmds "$ev" | cut -f2- | while IFS= read -r c; do
    [ -n "$c" ] || continue
    jq -n --arg e "$ev" --arg t "$T/low.jsonl" --argjson x "$extra" \
      '{hook_event_name:$e, session_id:"selfcheck", transcript_path:$t, cwd:"'"$T"'"} + $x' \
      | (cd "$T" && HOME="$T/home" sh -c "$c") >/dev/null 2>&1 \
      || printf '%s\n' "${c%% *}" >> "$T/hookfail.$ev"
  done
  if [ -s "$T/hookfail.$ev" ]; then
    bad "hook-$(echo "$ev" | tr 'A-Z' 'a-z')" "nonzero exit: $(tr '\n' ' ' < "$T/hookfail.$ev")"
  else
    ok "hook-$(echo "$ev" | tr 'A-Z' 'a-z')"
  fi
}
runhooks Stop '{}'
runhooks SessionStart '{"source":"startup"}'
runhooks PreCompact '{"trigger":"auto"}'
[ -f "$T/home/.claude/projects/$(echo "$T" | tr / -)/preserve.md" ] \
  && ok precompact-preserve || bad precompact-preserve 'wrote no preserve.md — compaction loses task state'

# context nudge must stay silent below its threshold and fire above it
NUDGE="$CD/hooks/context-nudge.sh"
if [ -x "$NUDGE" ]; then
  rm -f "$T/calls.notify-send" /tmp/claude-ctx-nudge-sc-lo /tmp/claude-ctx-nudge-sc-hi
  jq -n --arg t "$T/low.jsonl" '{session_id:"sc-lo",transcript_path:$t}' | sh "$NUDGE" >/dev/null 2>&1
  LO=$([ -f "$T/calls.notify-send" ] && echo fired || echo quiet)
  jq -n --arg t "$T/high.jsonl" '{session_id:"sc-hi",transcript_path:$t}' | sh "$NUDGE" >/dev/null 2>&1
  HI=$([ -f "$T/calls.notify-send" ] && echo fired || echo quiet)
  rm -f /tmp/claude-ctx-nudge-sc-lo /tmp/claude-ctx-nudge-sc-hi
  [ "$LO" = quiet ] && [ "$HI" = fired ] && ok context-nudge \
    || bad context-nudge "low=$LO high=$HI (want quiet/fired) — threshold vs 1m window"
else
  warn context-nudge 'not executable'
fi

# --- statusline -------------------------------------------------------------
if [ -r "$CD/statusline-command.sh" ]; then
  SJ=$(jq -n --arg d "$HOME" '{workspace:{current_dir:$d},model:{display_name:"Opus 5"},context_window:{used_percentage:42.3}}')
  A=$(date +%s%N)
  OUT=$(printf '%s' "$SJ" | bash "$CD/statusline-command.sh" 2>/dev/null)
  MS=$(( ($(date +%s%N) - A) / 1000000 ))
  if [ -z "$OUT" ]; then bad statusline 'empty output'
  elif [ "$MS" -gt 300 ]; then warn statusline "slow: ${MS}ms (renders on every turn)"
  else ok "statusline (${MS}ms)"; fi
else
  bad statusline 'script missing'
fi

# --- agents -----------------------------------------------------------------
ABAD=
for f in "$CD"/agents/*.md; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .md)
  fm=$(awk '/^---[[:space:]]*$/{c++; next} c==1' "$f")
  printf '%s' "$fm" | grep -qE "^name:[[:space:]]*$n[[:space:]]*$" || ABAD="$ABAD $n:name"
  printf '%s' "$fm" | grep -qE '^description:[[:space:]]*\S'          || ABAD="$ABAD $n:description"
  printf '%s' "$fm" | grep -qE '^model:[[:space:]]*(haiku|sonnet|opus|inherit)' || ABAD="$ABAD $n:model"
done
[ -z "$ABAD" ] && ok agents || bad agents "bad frontmatter:$ABAD (undeclared model silently runs opus)"

# --- skills -----------------------------------------------------------------
SBAD=
for d in "$CD"/skills/*; do
  [ -e "$d" ] || { SBAD="$SBAD $(basename "$d"):brokenlink"; continue; }
  n=$(basename "$d")
  # skills/synced is claude code's own bucket of bundled skills, refreshed by
  # the app and not authored here. it holds skills, it is not one.
  [ "$n" = synced ] && continue
  [ -f "$d/SKILL.md" ] || { SBAD="$SBAD $n:noskillmd"; continue; }
  fm=$(awk '/^---[[:space:]]*$/{c++; next} c==1' "$d/SKILL.md")
  printf '%s' "$fm" | grep -qE "^name:[[:space:]]*$n[[:space:]]*$" || SBAD="$SBAD $n:name"
  printf '%s' "$fm" | grep -qE '^description:[[:space:]]*\S'        || SBAD="$SBAD $n:description"
done
[ -z "$SBAD" ] && ok skills || bad skills "$SBAD"

# dangling symlinks anywhere in the config surface
DANG=$(find "$CD" -maxdepth 2 -xtype l \
  -not -path "$CD/projects/*" -not -path "$CD/plugins/*" -not -path "$CD/security/*" 2>/dev/null | tr '\n' ' ')
[ -z "$DANG" ] && ok symlinks || bad symlinks "dangling: $DANG"

# --- mcp --------------------------------------------------------------------
# claude reads ~/.claude.json (user scope) and project .mcp.json — nothing else.
if [ -f "$CD/mcp.json" ]; then
  bad mcp-deadconfig "$CD/mcp.json is never read by claude code — servers in it do not exist"
fi
if [ -f "$HOME/.claude.json" ]; then
  MBAD= MWARN=
  for sv in $(jq -r '.mcpServers // {} | keys[]' "$HOME/.claude.json" 2>/dev/null); do
    c=$(jq -r --arg s "$sv" '.mcpServers[$s].command' "$HOME/.claude.json")
    command -v "$c" >/dev/null 2>&1 || MBAD="$MBAD $sv:nocmd($c)"
  done
  [ -z "$MBAD" ] && ok mcp || bad mcp "$MBAD"
fi

# --- memory index -----------------------------------------------------------
# MEMORY.md is what loads each session; a file is only recallable if a path of
# links reaches it from there. an index entry pointing at a deleted file is a
# dead recall path; a file no path reaches is invisible no matter how good it is.
MDEAD=0 MDARK= NIDX=0
for M in "$CD"/projects/*/memory/MEMORY.md; do
  [ -f "$M" ] || continue
  NIDX=$((NIDX+1)); D=$(dirname "$M")
  FILES=$(cd "$D" && ls *.md 2>/dev/null | tr '\n' ' ')
  EDGES=$(grep -oHE '\]\([A-Za-z0-9._-]+\.md\)|\[\[[A-Za-z0-9._-]+\]\]' "$D"/*.md 2>/dev/null \
    | sed -e 's|^.*/||' -e 's|:\](|:|' -e 's|)$||' -e 's|:\[\[|:|' -e 's|\]\]$|.md|')
  R=$(printf '%s\n' "$EDGES" | awk -F: -v files="$FILES" '
    BEGIN { n = split(files, a, " "); for (i = 1; i <= n; i++) have[a[i]] = 1 }
    $1 == "MEMORY.md" && !($2 in have) { dead++ }
    $2 in have { edge[$1] = edge[$1] " " $2 }
    END {
      seen["MEMORY.md"] = 1; q = "MEMORY.md"
      while (q != "") {
        m = split(q, cur, " "); q = ""
        for (i = 1; i <= m; i++) {
          k = split(edge[cur[i]], e, " ")
          for (j = 1; j <= k; j++) if (!(e[j] in seen)) { seen[e[j]] = 1; q = q " " e[j] }
        }
      }
      for (i = 1; i <= n; i++) if (!(a[i] in seen)) dark++
      printf "%d %d", dead + 0, dark + 0
    }')
  MDEAD=$((MDEAD + ${R%% *}))
  [ "${R##* }" = 0 ] || MDARK="$MDARK $(basename "$(dirname "$D")"):${R##* }"
done
[ "$MDEAD" = 0 ] && ok "memory-index ($NIDX stores)" || bad memory-index "$MDEAD index entries point at deleted files"
[ -z "$MDARK" ] || warn memory-dark "no link path reaches these, so they never load —$MDARK"

# --- opsec ------------------------------------------------------------------
CRED="$CD/.credentials.json"
if [ -f "$CRED" ]; then
  P=$(stat -c %a "$CRED")
  R=$(git -C "$CD" ls-files --error-unmatch "$(basename "$CRED")" 2>/dev/null)
  if [ -n "$R" ]; then bad credentials 'tracked by git'
  elif [ "$P" != 600 ]; then bad credentials "mode $P, want 600"
  else ok credentials; fi
fi

# --- config drift (warn only: a dirty tree mid-session is normal) -----------
if git -C "$CD" rev-parse --git-dir >/dev/null 2>&1; then
  # $CD is a symlink into the repo; a symlink pathspec matches nothing, so
  # resolve it first or this check is permanently, silently green.
  R=$(CDPATH= cd -- "$CD" && pwd -P)
  DIRTY=$(cd "$R" && git status --short -- . 2>/dev/null | wc -l)
  AHEAD=$(git -C "$R" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
  [ "$DIRTY" -gt 0 ] && warn config-dirty "$DIRTY uncommitted — other machines will not see it"
  [ "${AHEAD:-0}" -gt 0 ] && warn config-unpushed "$AHEAD commits unpushed"
  [ "$DIRTY" -eq 0 ] && [ "${AHEAD:-0}" -eq 0 ] && ok config-synced
fi

# ---------------------------------------------------------------------------
if [ "$NFAIL" -gt 0 ]; then
  printf '\n%d passed, %d FAILED, %d warn\n' "$NPASS" "$NFAIL" "$NWARN"
  exit 1
fi
[ "$QUIET" = 1 ] || printf '\n%d passed, %d warn\n' "$NPASS" "$NWARN"
exit 0

# tests: sh selfcheck/faults.sh proves every check above can actually fail.

#!/bin/bash
# statusline — bashrc PS1 had nothing portable (only last-exit-code, which
# claude code doesn't expose). minimal line instead: dir / branch / model / ctx%
input=$(cat)

dir=$(jq -r '.workspace.current_dir // empty' <<< "$input")
[ -z "$dir" ] && dir=$PWD
name=$(basename "$dir")
model=$(jq -r '.model.display_name // empty' <<< "$input")
used=$(jq -r '.context_window.used_percentage // empty' <<< "$input")

branch=""
if git -C "$dir" --no-optional-locks rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)
fi

y='\033[38;5;226m'  # yellow
o='\033[38;5;208m'  # orange
w='\033[38;5;231m'  # white
g='\033[38;5;46m'   # green
r='\033[38;5;196m'  # red
n='\033[0m'

out="${y}${name}${n}"
[ -n "$branch" ] && out="$out ${o}${branch}${n}"
[ -n "$model" ] && out="$out ${w}${model}${n}"
if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used")
  if ((pct >= 90)); then c=$r; elif ((pct >= 70)); then c=$y; else c=$g; fi
  out="$out ${c}${pct}%${n}"
fi

printf '%b' "$out"

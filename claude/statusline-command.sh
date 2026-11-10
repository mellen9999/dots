#!/bin/bash
# statusline: dir branch model effort ctx 5h 7d — ansi 0-7 only
# ctx is measured against the autocompact window (400k), not the raw 1m window
input=$(cat)

IFS=$'\x1f' read -r dir model effort ctx five week < <(jq -r '[
  (.workspace.current_dir // ""),
  (.model.display_name // ""),
  (.effort.level // ""),
  ((.context_window.current_usage // null) as $u | if $u then (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) else ((.context_window.used_percentage // 0) * (.context_window.context_window_size // 1000000) / 100 | floor) end | tostring),
  ((.rate_limits.five_hour.used_percentage // "") | tostring),
  ((.rate_limits.seven_day.used_percentage // "") | tostring)
] | join("\u001f")' <<< "$input")
[ -z "$dir" ] && dir=$PWD

branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)

r='\033[31m' g='\033[32m' y='\033[33m' c='\033[36m' w='\033[37m' n='\033[0m'
lvl() { if (($1 >= 90)); then printf %s "$r"; elif (($1 >= 70)); then printf %s "$y"; else printf %s "$g"; fi; }

out="${y}$(basename "$dir")${n}"
[ -n "$branch" ] && out="$out ${c}${branch}${n}"
[ -n "$model" ] && out="$out ${w}${model,,}${n}"
[ -n "$effort" ] && out="$out ${w}${effort}${n}"
if [ "${ctx:-0}" -gt 0 ]; then
  p=$((ctx * 100 / 400000))
  out="$out $(lvl $p)ctx ${p}%${n}"
fi
for pair in "5h:$five" "7d:$week"; do
  v=${pair#*:}; [ -z "$v" ] && continue
  p=$(printf '%.0f' "$v")
  out="$out $(lvl "$p")${pair%%:*} ${p}%${n}"
done

printf '%b' "$out"

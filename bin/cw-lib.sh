#!/usr/bin/env bash
# cw-lib.sh — shared truth for cw / cw-land / cw-clean.
#
# All three used to hardcode `main`. That is wrong on any repo whose default
# branch is `master`, and on 2026-08-16 that was 4 of mellen's 17 repos
# (bazaarinfo, comfyui, gbs-control, scart-breakout) — `cw` there resolved no
# base and died on `git worktree add … main`. Three copies of the same
# assumption is also three places to fix it, so it lives here once.
#
# Source it; do not execute it.

# The ref a new worktree should branch FROM, most authoritative first:
#   1. origin's own HEAD symref — what the remote says its default is
#   2. the conventional remote branches
#   3. a local branch, for repos with no remote at all
#   4. current HEAD, so a detached or oddly-named checkout still works
# Prints the ref; returns 1 only if the repo has no commits.
cw_base_ref() {
  local c
  if c=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s\n' "$c"; return 0
  fi
  # Not set (common — clones only get it if asked). Learn it without a network
  # round trip where possible; silence failure, we have fallbacks.
  if git remote set-head origin -a >/dev/null 2>&1 &&
     c=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s\n' "$c"; return 0
  fi
  for c in origin/main origin/master; do
    git rev-parse -q --verify "$c" >/dev/null 2>&1 && { printf '%s\n' "$c"; return 0; }
  done
  for c in main master; do
    git rev-parse -q --verify "refs/heads/$c" >/dev/null 2>&1 && { printf '%s\n' "$c"; return 0; }
  done
  git rev-parse -q --verify HEAD >/dev/null 2>&1 && { printf 'HEAD\n'; return 0; }
  return 1
}

# The bare branch name behind that ref — what `push origin HEAD:<name>` needs.
# `origin/master` → `master`; a local `main` stays `main`.
cw_base_branch() {
  local r; r=$(cw_base_ref) || return 1
  printf '%s\n' "${r#origin/}"
}

# True when this repo has an `origin` to land against. cw works without one
# (a local-only repo still gets isolation); cw-land does not.
cw_has_origin() {
  git remote get-url origin >/dev/null 2>&1
}

# cw puts worktrees at .worktrees/ INSIDE the repo, so an unignored one shows up
# as untracked and makes the tree dirty — which is not cosmetic: heatsync's
# deploy.sh refuses a dirty tree by design, and pre-commit gates read the same
# signal. 13 of 17 repos did not ignore it.
#
# Written to .git/info/exclude, never .gitignore: it is per-clone, untracked,
# and needs no commit, so this never edits a file the repo's owner has to review
# or that shows up in someone else's diff.
cw_exclude_worktrees() {
  git check-ignore -q .worktrees 2>/dev/null && return 0
  local common excl
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  excl="$common/info/exclude"
  mkdir -p "$(dirname "$excl")" 2>/dev/null || return 0
  grep -qxF '.worktrees/' "$excl" 2>/dev/null && return 0
  printf '\n# cw worktrees — local only, never committed\n.worktrees/\n' >> "$excl" 2>/dev/null || return 0
}

# ── tmux window naming ────────────────────────────────────────────────────────
# A tab reading `260817-152649-3660759` says nothing about what that session is
# doing, and with seven running at once that is every tab. tmux gets the name
# from the worktree directory (automatic-rename-format falls back to the path
# basename for bash/claude panes), and that directory has to stay unique and
# timestamped for cw-clean to reap it — so name the WINDOW instead: the repo
# folder, plus the topic word from the prompt when there is one.
#
# The worktree directory carries the repo name too (see `cw`), which looks
# redundant with this but is not: Claude builds a session's cross-session peer
# name from the cwd basename, never from the tmux window, so dropping it there
# makes every worktree session anonymous to its siblings again.

# Words that show up in every prompt and identify nothing.
CW_STOPWORDS='the a an and or of to in on at for with from into by is are be it
this that we i you they not no please pls plz can will just also then so if when
do does did done make made get got let use used run go add adds fix fixes update
updates change changes check checks look see new all any some more very really
thing things stuff now here there what why how who where which about like need needs
want wants try help ok okay yes yeah still again out up down over off
hi hey hello yo sup thanks thank sorry lets
scan write create remove delete rename move show list print read open start stop
kill finish continue keep put pull send give tell take work working'

cw_is_stopword() {
  local w
  for w in $CW_STOPWORDS; do
    if [ "$w" = "$1" ]; then return 0; fi
  done
  return 1
}

# First word of the prompt that carries meaning, lowercased and capped at 12
# chars. Returns 1 when the prompt is empty or all filler.
cw_topic_word() {
  local w
  for w in $(printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' ' '); do
    if [ "${#w}" -lt 3 ]; then continue; fi
    if cw_is_stopword "$w"; then continue; fi
    printf '%s\n' "${w:0:12}"
    return 0
  done
  return 1
}

# cw_window_name <folder> [prompt] [own-window-id] → `heatsync`, or
# `heatsync-emotes` when the prompt names a topic. Unique against the windows
# already open, so two sessions on one repo read `heatsync` and `heatsync2`
# rather than two identical tabs.
#
# The third argument is the window doing the asking, and it must be excluded:
# automatic-rename has ALREADY named that window after the repo folder (it is
# the pane's cwd), so without this every first session reads `heatsync2` —
# bumped out of the way by itself.
cw_window_name() {
  local folder="$1" topic name base n taken self="${3-}"
  folder=$(printf '%s' "$folder" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')
  folder="${folder#-}"; folder="${folder%-}"
  [ -n "$folder" ] || folder=claude
  topic=$(cw_topic_word "${2-}") || topic=''
  name="$folder"
  if [ -n "$topic" ] && [ "$topic" != "$folder" ]; then name="$folder-$topic"; fi
  name="${name:0:20}"; name="${name%-}"
  base="$name"
  taken=$(tmux list-windows -a -F '#{window_id} #W' 2>/dev/null) || taken=''
  taken=$(printf '%s\n' "$taken" | grep -v "^${self:-@_none_} " | cut -d' ' -f2-)
  n=2
  while printf '%s\n' "$taken" | grep -qxF "$name"; do
    if [ "$n" -gt 99 ]; then break; fi
    name="$base$n"; n=$((n + 1))
  done
  printf '%s\n' "$name"
}

# cw_claim_window <folder> [prompt] — name this window and pin it so
# automatic-rename cannot put the worktree timestamp back. Restored by
# cw_release_window on exit: an abandoned pane still wearing a finished
# session's name is a tab that lies.
cw_claim_window() {
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  # -t "$TMUX_PANE", never a bare display-message: bare reads the session's
  # ACTIVE window, so a cw started in a background pane would rename whatever
  # tab mellen happens to be looking at.
  CW_WIN=$(tmux display-message -pt "$TMUX_PANE" '#{window_id}' 2>/dev/null) || return 0
  [ -n "$CW_WIN" ] || return 0
  CW_WIN_NAME=$(tmux display-message -pt "$CW_WIN" '#W' 2>/dev/null) || CW_WIN_NAME=''
  CW_WIN_AUTO=$(tmux show-window-options -vt "$CW_WIN" automatic-rename 2>/dev/null) || CW_WIN_AUTO=on
  tmux set-window-option -t "$CW_WIN" automatic-rename off >/dev/null 2>&1 || return 0
  tmux rename-window -t "$CW_WIN" "$(cw_window_name "$1" "${2-}" "$CW_WIN")" >/dev/null 2>&1 || true
}

cw_release_window() {
  [ -n "${CW_WIN:-}" ] || return 0
  tmux set-window-option -t "$CW_WIN" automatic-rename "${CW_WIN_AUTO:-on}" >/dev/null 2>&1 || true
  if [ "${CW_WIN_AUTO:-on}" = off ] && [ -n "${CW_WIN_NAME:-}" ]; then
    tmux rename-window -t "$CW_WIN" "$CW_WIN_NAME" >/dev/null 2>&1 || true
  fi
}

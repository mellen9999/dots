#!/usr/bin/env bash
# setup.sh — turn a fresh arch install into this setup. safe to re-run any time.
#
#   setup.sh            do everything (asks for your password once)
#   setup.sh check      report drift only, changes nothing
#   setup.sh <step>     run one step: pacman pkgs aur etc repos dots services handoff
#
# what goes on a box: setup/hosts/<hostname> (or hosts/default) → setup/pkgs/*.txt,
# setup/etc.conf, link.conf
set -Eeuo pipefail

# shellcheck source=setup/lib.sh
. "$(dirname "$(readlink -f "$0")")/setup/lib.sh"

STEPS=(pacman pkgs aur etc repos dots services handoff)
# shellcheck source=/dev/null
for f in "$SETUP"/steps/*.sh; do . "$f"; done

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

preflight() {
  ((EUID)) || die "run as your user, not root (it asks for sudo itself)"
  [[ -f /etc/arch-release ]] || die "arch linux only"
}

# links + local PKGBUILDs point at ~/sync/config, so changes only run from there
home_repo() { [[ $CONF == "$HOME/sync/config" ]]; }

check() {
  local s
  printf 'checking %s (profile: %s, groups: %s)\n' "$HOST" "$PROFILE" "${groups[*]}"
  for s in pacman pkgs etc repos dots services; do
    head1 "$s"
    if [[ $s == dots ]] && ! home_repo; then warn "skipped: not running from ~/sync/config"; continue; fi
    "check_$s"
  done
  echo
  if ((DRIFT)); then printf '%s%d drift item(s)%s — fix with: setup.sh\n' "$Y" "$DRIFT" "$N"; exit 1; fi
  printf '%sin sync%s\n' "$G" "$N"
}

apply() { # [only-this-step]
  home_repo || die "repo must live at ~/sync/config (it's at $CONF)"
  mkdir -p "$HOME/.local/state/setup"
  local log=$HOME/.local/state/setup/$TS.log
  exec > >(tee -a "$log") 2>&1
  printf 'setup on %s (profile: %s) — log: %s\n' "$HOST" "$PROFILE" "$log"
  sudo_start
  trap sudo_stop EXIT
  trap '((BASH_SUBSHELL)) || printf "\n%ssetup: step \"%s\" failed (line %s). fix it, then run setup.sh again — it picks up where it left off%s\n" "$R" "$CUR_STEP" "$LINENO" "$N"' ERR
  for CUR_STEP in "${STEPS[@]}"; do
    [[ -z ${1:-} || $1 == "$CUR_STEP" ]] || continue
    head1 "$CUR_STEP"
    "apply_$CUR_STEP"
  done
  printf '\n%sdone%s — safe to re-run any time; drift report: setup.sh check\n' "$G" "$N"
}

main() {
  local cmd=${1:-}
  case $cmd in
    -h | --help | help) usage ;;
  esac
  [[ -z $cmd || $cmd == check || " ${STEPS[*]} " == *" $cmd "* ]] || usage 1
  preflight
  load_profile
  if [[ $cmd == check ]]; then check; else apply "$cmd"; fi
}

main "$@"

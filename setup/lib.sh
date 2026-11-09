# shellcheck shell=bash disable=SC2034  # globals here are read by the steps
# shared helpers for setup.sh — sourced, never run

CONF=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
SETUP=$CONF/setup
HOST=$(uname -n)
TS=$(date +%Y%m%d-%H%M%S)
REBOOT_WHY=()
DRIFT=0

if [[ -t 1 ]]; then
  B=$'\e[1m' R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' N=$'\e[0m'
else
  B='' R='' G='' Y='' N=''
fi

head1() { printf '\n%s== %s%s\n' "$B" "$*" "$N"; }
ok()    { printf '  %sok%s    %s\n' "$G" "$N" "$*"; }
did()   { printf '  %sdone%s  %s\n' "$G" "$N" "$*"; }
warn()  { printf '  %swarn%s  %s\n' "$Y" "$N" "$*"; }
drift() { printf '  %sdrift%s %s\n' "$Y" "$N" "$*"; DRIFT=$((DRIFT + 1)); }
die()   { printf '%ssetup: %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
reboot_for() { REBOOT_WHY+=("$1"); }

# --- profile -----------------------------------------------------------------

root_is_btrfs() { [[ $(findmnt -no FSTYPE /) == btrfs ]]; }
has_battery()   { compgen -G '/sys/class/power_supply/BAT*' >/dev/null; }
has_amd_gpu() {
  local d
  for d in /sys/bus/pci/devices/*; do
    [[ $(<"$d/class") == 0x03* && $(<"$d/vendor") == 0x1002 ]] && return 0
  done
  return 1
}

# hosts/<hostname> (falls back to hosts/default) + hardware it can see
load_profile() {
  local f=$SETUP/hosts/$HOST
  PROFILE=$HOST
  [[ -f $f ]] || { PROFILE=default; f=$SETUP/hosts/default; }
  groups=() services=() user_units=() user_groups=() repos=()
  # shellcheck source=/dev/null
  . "$f"
  if root_is_btrfs; then groups+=(btrfs); services+=(snapper-timeline.timer snapper-cleanup.timer); fi
  if has_amd_gpu; then groups+=(hw-amd); fi
  if has_battery; then groups+=(laptop); services+=(bluetooth); fi
}

# --- packages ----------------------------------------------------------------

pkgs_in() {
  local g
  for g; do
    [[ -f $SETUP/pkgs/$g.txt ]] || die "unknown package group: $g"
    sed -E 's/#.*//; s/[[:space:]]+//g; /^$/d' "$SETUP/pkgs/$g.txt"
  done
}

is_local() { [[ -f $CONF/pkg/$1/PKGBUILD ]]; }

# sorts the profile's packages into OFFICIAL / AUR / LOCAL / MISSING_* arrays
sort_pkgs() {
  local p
  local -A sync=() have=()
  while read -r p; do sync[$p]=1; done < <(pacman -Slq)
  while read -r p; do have[$p]=1; done < <(pacman -Qq)
  OFFICIAL=() AUR=() LOCAL=() MISSING_OFFICIAL=() MISSING_AUR=() MISSING_LOCAL=()
  while read -r p; do
    if is_local "$p"; then
      LOCAL+=("$p"); [[ -n ${have[$p]:-} ]] || MISSING_LOCAL+=("$p")
    elif [[ -n ${sync[$p]:-} ]]; then
      OFFICIAL+=("$p"); [[ -n ${have[$p]:-} ]] || MISSING_OFFICIAL+=("$p")
    else
      AUR+=("$p"); [[ -n ${have[$p]:-} ]] || MISSING_AUR+=("$p")
    fi
  done < <(pkgs_in "${groups[@]}" | sort -u)
}

# --- /etc --------------------------------------------------------------------

# "dest src mode" per line for this host; a host line beats an all-hosts line
etc_entries() {
  local line src dest host mode
  local -A pick=() pinned=()
  while IFS= read -r line; do
    line=${line%%#*}
    [[ -z ${line//[[:space:]]/} ]] && continue
    IFS=: read -r src dest host mode <<<"$line"
    if [[ -n $host ]]; then
      [[ $host == "$HOST" ]] || continue
      pinned[$dest]=1
    elif [[ -n ${pinned[$dest]:-} ]]; then
      continue
    fi
    pick[$dest]="$src ${mode:-644}"
  done <"$SETUP/etc.conf"
  for dest in "${!pick[@]}"; do printf '%s %s\n' "$dest" "${pick[$dest]}"; done | sort
}

# --- sudo --------------------------------------------------------------------

# one password prompt for the whole run
sudo_start() {
  sudo -v || die "sudo failed — is $USER in the wheel group?"
  ( while sleep 50; do sudo -n -v 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE=$!
}
sudo_stop() { [[ -n ${SUDO_KEEPALIVE:-} ]] && kill "$SUDO_KEEPALIVE" 2>/dev/null; return 0; }

# shellcheck shell=bash disable=SC2154  # profile arrays come from lib.sh
# official repo packages, one transaction after a full upgrade (never a partial -Sy)

apply_pkgs() {
  sudo pacman -Syu --noconfirm
  sort_pkgs
  if ((${#MISSING_OFFICIAL[@]})); then
    sudo pacman -S --needed --noconfirm "${MISSING_OFFICIAL[@]}"
    did "${#MISSING_OFFICIAL[@]} packages installed"
  else
    ok "${#OFFICIAL[@]} official packages"
  fi
}

check_pkgs() {
  sort_pkgs
  local p d0=$DRIFT
  for p in "${MISSING_OFFICIAL[@]}" "${MISSING_AUR[@]}" "${MISSING_LOCAL[@]}"; do drift "not installed: $p"; done
  # explicit leaves no list mentions: add to a group, or remove from the box
  local -A known=()
  while read -r p; do known[$p]=1; done < <(pkgs_in "${groups[@]}" stage1 manual)
  while read -r p; do [[ -n ${known[$p]:-} ]] || drift "in no list: $p"; done < <(pacman -Qqet)
  ((DRIFT > d0)) || ok "packages match profile ($PROFILE)"
}

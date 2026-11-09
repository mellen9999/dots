# shellcheck shell=bash disable=SC2154  # profile arrays come from lib.sh
# paru (from source — paru-bin breaks on libalpm bumps), local PKGBUILDs, then AUR

DWL=$HOME/code/external/dwl

rust_ready() {
  command -v rustup >/dev/null || return 0
  rustup default 2>/dev/null | grep -q . && return 0
  rustup default stable >/dev/null
  did "rust stable toolchain"
}

paru_bootstrap() {
  if command -v paru >/dev/null; then ok "paru"; return; fi
  # build on disk: /tmp is ram on arch, and a rust build there runs small boxes out of memory
  local tmp=$HOME/.cache/setup/paru
  rm -rf "$tmp"
  git clone -q https://aur.archlinux.org/paru.git "$tmp"
  (cd "$tmp" && makepkg -s --noconfirm && sudo pacman -U --noconfirm paru-[0-9]*.pkg.tar.zst)
  rm -rf "$tmp"
  did "paru built from source"
}

# the patched dwl lives in a local fork; the PKGBUILD builds from it
dwl_fork() {
  if [[ ! -d $DWL/.git ]]; then
    git clone -q -o github https://github.com/mellen9999/dwl.git "$DWL"
    git -C "$DWL" remote add origin https://codeberg.org/dwl/dwl.git
    did "dwl fork → $DWL"
  fi
  # pkgver() runs git describe; release tags only exist upstream
  git -C "$DWL" describe --tags >/dev/null 2>&1 || git -C "$DWL" fetch -q --tags origin
  [[ -e $DWL/config.h ]] || ln -s "$CONF/dwl-config.h" "$DWL/config.h"
}

apply_aur() {
  rust_ready
  paru_bootstrap
  sort_pkgs
  local p
  for p in "${MISSING_LOCAL[@]}"; do
    [[ $p == dwl-mellen ]] && dwl_fork
    (cd "$CONF/pkg/$p" && makepkg -sic --noconfirm)
    did "$p (local build)"
  done
  local need=()
  for p in "${MISSING_AUR[@]}"; do [[ $p == paru ]] || need+=("$p"); done
  if ((${#need[@]})); then
    paru -S --needed --noconfirm --skipreview "${need[@]}"
    did "${#need[@]} aur packages"
  else
    ok "${#AUR[@]} aur + ${#LOCAL[@]} local packages"
  fi
}

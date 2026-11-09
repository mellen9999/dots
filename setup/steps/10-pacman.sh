# shellcheck shell=bash disable=SC2154  # profile arrays come from lib.sh
# multilib on (steam + lib32 drivers). targeted edit, not a pacman.conf copy: no .pacnew churn

multilib_on() { grep -q '^\[multilib\]' /etc/pacman.conf; }

apply_pacman() {
  if multilib_on; then ok "multilib"; return; fi
  sudo cp -a /etc/pacman.conf "/etc/pacman.conf.setup-$TS"
  sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
  multilib_on || die "could not enable multilib — /etc/pacman.conf backed up to /etc/pacman.conf.setup-$TS"
  did "multilib enabled"
}

check_pacman() { if multilib_on; then ok "multilib"; else drift "multilib off"; fi; }

# shellcheck shell=bash disable=SC2154  # profile arrays come from lib.sh
# what a script can't (or shouldn't) do: logins, secrets, firmware. only lists what's still undone

apply_handoff() {
  local todo=() u
  git config user.email >/dev/null || todo+=("your git name + email:  git config -f ~/.gitconfig.local user.name 'you' && git config -f ~/.gitconfig.local user.email 'you@example.com'")
  ((${#repos[@]})) && ! gh auth status >/dev/null 2>&1 && todo+=("log in to github, then run setup.sh again to clone repos:  gh auth login")
  command -v tailscale >/dev/null && ! tailscale status >/dev/null 2>&1 && todo+=("join the tailnet (open the link it prints — phone is fine):  sudo tailscale up")
  command -v gh >/dev/null && [[ ! -f $HOME/.ssh/id_ed25519 ]] && todo+=("make this box's ssh key and add it to github:  ssh-keygen -t ed25519 && gh ssh-key add ~/.ssh/id_ed25519.pub")
  if command -v syncthing >/dev/null && (($(cat "$HOME"/.local/state/syncthing/config.xml "$HOME"/.config/syncthing/config.xml 2>/dev/null | grep -c '<device ') < 2)); then
    todo+=("pair syncthing — on your other box add this device id:  $(syncthing device-id 2>/dev/null || echo 'syncthing device-id')")
  fi
  [[ " ${user_units[*]} " != *" backup-restic.timer "* || -f $HOME/.config/restic/password ]] || todo+=("backups: copy ~/.config/restic/ (password, targets, excludes.txt) from your password vault")
  [[ $PROFILE == default || -f $HOME/.config/alert.env ]] || todo+=("phone alerts: copy ~/.config/alert.env (NTFY_TOPIC=...) from heatpc")
  command -v atuin >/dev/null && [[ ! -f $HOME/.local/share/atuin/key ]] && todo+=("shell history sync:  atuin login")
  if ! bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
    todo+=("secure boot (optional, needs the bios twice):
       1. reboot → bios → secure boot → clear keys / setup mode → save
       2. sudo sbctl create-keys && sudo sbctl enroll-keys -m
       3. sudo sbctl verify  →  for every file it lists:  sudo sbctl sign -s <file>
       4. reboot → bios → secure boot on")
  fi
  if pacman -Q apparmor >/dev/null 2>&1 && ! grep -qs apparmor /sys/kernel/security/lsm; then
    todo+=("apparmor: add  lsm=landlock,lockdown,yama,integrity,apparmor,bpf  to /etc/kernel/cmdline, then  sudo mkinitcpio -P  and reboot")
  fi
  while read -r u; do todo+=("failed unit: $u  →  journalctl -u $u -n 50"); done \
    < <(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
  while read -r u; do todo+=("failed user unit: $u  →  journalctl --user -u $u -n 50"); done \
    < <(systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
  ((${#REBOOT_WHY[@]})) && todo+=("reboot once to finish (${REBOOT_WHY[*]})")

  if ((!${#todo[@]})); then ok "nothing left to do by hand"; return; fi
  local i=1 t
  for t in "${todo[@]}"; do printf '  %d. %s\n' "$i" "$t"; i=$((i + 1)); done
}

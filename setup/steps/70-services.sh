# shellcheck shell=bash disable=SC2154  # profile arrays come from lib.sh
# groups, system units, linger, user units — all from the host profile

unit_exists() { systemctl "${@:1:$#-1}" cat -- "${!#}" >/dev/null 2>&1; } # [--user] <unit>

apply_services() {
  local g s
  for g in "${user_groups[@]}"; do
    getent group "$g" >/dev/null || continue
    id -nG "$USER" | grep -qw "$g" && continue
    sudo usermod -aG "$g" "$USER"
    did "joined group $g"; reboot_for "group $g"
  done
  for s in "${services[@]}"; do
    if ! unit_exists "$s"; then warn "no unit $s (package missing?)"; continue; fi
    if systemctl is-enabled -q "$s" 2>/dev/null; then ok "$s"; continue; fi
    sudo systemctl enable --now "$s"
    did "$s"
  done
  # user timers keep running when logged out (backups, health checks)
  if [[ ! -e /var/lib/systemd/linger/$USER ]]; then sudo loginctl enable-linger "$USER"; did "linger"; fi
  systemctl --user daemon-reload
  for s in "${user_units[@]}"; do
    if ! unit_exists --user "$s"; then warn "no user unit $s"; continue; fi
    if systemctl --user is-enabled -q "$s" 2>/dev/null; then ok "$s (user)"; continue; fi
    systemctl --user enable --now "$s"
    did "$s (user)"
  done
}

check_services() {
  local g s d0=$DRIFT
  for g in "${user_groups[@]}"; do
    getent group "$g" >/dev/null || continue
    id -nG "$USER" | grep -qw "$g" || drift "not in group $g"
  done
  for s in "${services[@]}"; do systemctl is-enabled -q "$s" 2>/dev/null || drift "not enabled: $s"; done
  [[ -e /var/lib/systemd/linger/$USER ]] || drift "linger off"
  for s in "${user_units[@]}"; do systemctl --user is-enabled -q "$s" 2>/dev/null || drift "not enabled: $s (user)"; done
  ((DRIFT > d0)) || ok "services match profile"
}

#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="$CONF_DIR/link.conf"
HOSTNAME="$(hostname)"
DRY_RUN=false

[[ "${1:-}" == "-n" ]] && DRY_RUN=true

backup_dir="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
backed_up=false

log() { printf '%s\n' "$*"; }

backup() {
  local target="$1"
  if ! $backed_up; then
    mkdir -p "$backup_dir"
    backed_up=true
  fi
  local dest="$backup_dir${target#$HOME}"
  mkdir -p "$(dirname "$dest")"
  mv "$target" "$dest"
  log "  backed up → $dest"
}

while IFS= read -r line; do
  line="${line%%#*}"
  [[ -z "${line// /}" ]] && continue

  IFS=: read -r src target host <<< "$line"
  src="${src// /}"
  target="${target// /}"
  host="${host// /}"

  [[ -n "$host" && "$host" != "$HOSTNAME" ]] && continue

  target="${target/#\~/$HOME}"
  src_path="$CONF_DIR/$src"

  if [[ ! -e "$src_path" ]]; then
    log "SKIP $src (source missing)"
    continue
  fi

  if [[ -L "$target" && "$(readlink "$target")" == "$src_path" ]]; then
    log "OK   $target"
    continue
  fi

  if $DRY_RUN; then
    log "WOULD link $src_path → $target"
    [[ -e "$target" && ! -L "$target" ]] && log "  (existing file/dir will be backed up)"
    continue
  fi

  if [[ -L "$target" ]]; then
    rm "$target"
    log "  removed stale symlink $target"
  elif [[ -e "$target" ]]; then
    backup "$target"
  fi

  mkdir -p "$(dirname "$target")"
  ln -s "$src_path" "$target"
  log "LINK $src_path → $target"
done < "$CONF_FILE"

# shellcheck shell=bash disable=SC2154  # profile arrays come from lib.sh
# ~/.claude → the synced claude dir (once claude code is installed), then link.sh for every dotfile

apply_dots() {
  if ! command -v claude >/dev/null; then :
  elif [[ -L $HOME/.claude ]]; then ok "$HOME/.claude"
  elif [[ -e $HOME/.claude ]]; then warn "$HOME/.claude is a real folder — left alone (move it aside and re-run to link it)"
  else ln -s "$CONF/claude" "$HOME/.claude"; did "$HOME/.claude → $CONF/claude"
  fi
  "$CONF/link.sh" | grep -v '^OK ' | sed 's/^/  /' || true
  ok "dotfiles linked"
}

check_dots() {
  local l d0=$DRIFT
  ! command -v claude >/dev/null || [[ -L $HOME/.claude ]] || drift "$HOME/.claude is not linked to $CONF/claude"
  while read -r l; do drift "${l#WOULD }"; done < <("$CONF/link.sh" -n | grep '^WOULD')
  ((DRIFT > d0)) || ok "dotfiles linked"
}

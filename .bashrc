# shared bashrc — single source of truth, sourced by all machines
[[ $- != *i* ]] && return

# orphaned mosh-servers self-reap after 7d (server-side env doesn't survive ssh remote cmds on arch)
alias mosh='mosh --server="MOSH_SERVER_NETWORK_TMOUT=604800 mosh-server"'

# === Core ===
set -o vi
export EDITOR=vis
export VISUAL=vis
[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin/sync-bin:$HOME/.local/bin:$PATH"
[[ ":$PATH:" != *":$HOME/scripts:"* ]] && export PATH="$HOME/scripts:$PATH"

# === History ===
HISTSIZE=50000
HISTFILESIZE=50000
HISTCONTROL=ignoredups:ignorespace
shopt -s histappend cdspell dirspell
# append only — `history -c; history -r` re-read the whole file every prompt, which
# makes every pane serve up other panes' commands and scales with HISTSIZE
PROMPT_COMMAND='__e=$?; history -a'

# === Prompt ===
# mode indicator (white=insert, red=normal) comes from .inputrc; PS1 adds the last
# exit code in red, only when it failed. \001/\002 = readline's non-printing markers
# (\[ \] don't work inside a command substitution)
__ps1() { ((__e)) && printf '\001\e[91m\002 %s\001\e[0m\002' "$__e"; }
PS1='$(__ps1) '

# === Tools ===
[[ -f /usr/share/bash-completion/bash_completion ]] && source /usr/share/bash-completion/bash_completion
[[ -f /usr/share/fzf/key-bindings.bash ]] && source /usr/share/fzf/key-bindings.bash
[[ -f /usr/share/fzf/completion.bash ]] && source /usr/share/fzf/completion.bash
eval "$(zoxide init bash --cmd j)"
# atuin owns ctrl-r (global fuzzy search across machines); up-arrow stays bash's own,
# so plain up is still THIS pane's last command. sourced after fzf so ctrl-r lands here.
command -v atuin &>/dev/null && eval "$(atuin init bash --disable-up-arrow)"

# === Modern CLI (only if installed) ===
# never shadow a POSIX name — rg/fd/dust/procs don't take grep/find/du/ps flags, so a
# pasted `find . -name '*.log' -delete` or `grep -rl` would silently do the wrong thing.
# call rg/fd/dust/procs/btm/difft by their own names; they're already short.
command -v eza &>/dev/null && alias l='eza' && alias ll='eza -la' && alias lt='eza --tree --level=2'
command -v bat &>/dev/null && alias c='bat --plain --paging=never'
alias vi='vis'
alias vim='vis'

# === Claude Code ===
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000
export BASH_DEFAULT_TIMEOUT_MS=600000
export BASH_MAX_TIMEOUT_MS=600000
alias claude="claude --dangerously-skip-permissions --chrome"
q() { command claude -p "$*"; }

# === Music ===
alias music='mpv --no-video --volume=50 --shuffle --loop-playlist ~/sync/music/'

# === SDR ===
fm() { rtl_fm -M wbfm -f "${1:?freq required}" -s 200000 -r 48000 -g 40.2 2>/dev/null | aplay -r 48000 -f S16_LE -t raw -c 1; }

# === WM ===
[[ -f ~/sync/config/bin/wm ]] && alias wm='~/sync/config/bin/wm'

# === SSH agent (fixed socket, one agent shared across all shells) ===
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/tmp}/ssh-agent.sock"
# ssh-add -l: 0=keys loaded, 1=agent up but empty, 2=agent unreachable. only (re)spawn on 2.
ssh-add -l &>/dev/null
if [[ $? -eq 2 ]]; then
    rm -f "$SSH_AUTH_SOCK"
    eval "$(ssh-agent -a "$SSH_AUTH_SOCK" -s)" > /dev/null
    ssh-add ~/.ssh/id_ed25519 2>/dev/null
fi

# === Tmux terminal-aware colors ===
# generates .tmux.local.conf BEFORE tmux starts — no async if-shell needed
if [[ "$TERM" = "linux" ]]; then
  cat > ~/.tmux.local.conf <<'EOF'
set -g default-terminal "linux"
EOF
else
  cat > ~/.tmux.local.conf <<'EOF'
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc"
EOF
fi

# === cmdchamp save sync ===
# The save lives on two devices. Merge before and after a session so neither
# side loses progress — never blocks play when the other one is unreachable.
cmdchamp() {
  # Only a bare `cmdchamp` plays. reset/test/version take no sync — and reset
  # especially must not, since the merge would restore what it just wiped.
  if (($#)) || ! command -v cc-sync >/dev/null; then command cmdchamp "$@"; return; fi
  cc-sync || printf '\ncc-sync: starting unsynced — the titan is unreachable\n\n' >&2
  command cmdchamp
  local rc=$?
  cc-sync || printf '\ncc-sync: NOT synced back — run cc-sync once the titan is up\n' >&2
  return $rc
}

# push an exact command onto titan's android clipboard. payload rides ssh stdin,
# never a terminal or a shell arg, so nothing mangles it (unlike a paste through
# foot). no arg -> sends this box's clipboard; with args -> that literal string.
# ssh, not mosh: mosh is interactive-only and can't pipe stdin. termux-clipboard-set
# is async (~<1s) -- paste on the phone a beat later.
titanclip() { { [ "$#" -gt 0 ] && printf %s "$*" || wl-paste -n; } | ssh titan termux-clipboard-set; }

# xos build + selftest with a scrollable log and a failures summary at the end,
# so a fail is readable without scrollback (mosh eats it). no arg -> `all` then
# selftest; args -> that build.sh verb only (e.g. `xosbuild ci`). the passphrase
# prompt still works -- tee only captures stdout, `read` still reads the tty. NEVER
# put the passphrase on the command line (shell history + ps leak it).
xosbuild() {
	local log=~/xos-build.log rc
	( cd ~/projects/xos || exit 1
	  if [ "$#" -gt 0 ]; then ./build.sh "$@"; else ./build.sh all && ./selftest.sh; fi ) 2>&1 | tee "$log"
	rc=${PIPESTATUS[0]}
	echo; echo "=== exit $rc; failures ==="
	# a gate FAIL, a selftest bad, a repro miss, or a build error/abort -- and if
	# the run died with none of those words matched, show the tail so nothing hides.
	grep -niE 'FAIL|not reproducible|error:|abort|refus' "$log" \
		|| { [ "$rc" = 0 ] && echo '(clean)' || { echo '(no matched line -- tail:)'; tail -20 "$log"; }; }
	return "$rc"
}

# === Local overrides ===
[[ -f ~/.bashrc.local ]] && source ~/.bashrc.local

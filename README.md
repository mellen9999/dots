# dots

daily-driver linux config: dwl, foot, tmux, bash, mako, btop, mpv, chromium/vivaldi
privacy hardening, and the claude code setup (hooks, skills, selfcheck) i actually run.

pulled from a private monorepo — machine-specific infra (backups, NAS, router,
business tooling) stays out. this is the generic, reusable half.

## what's here

- **shell** — `.bashrc`, `.tmux.conf`, `.inputrc`, `.gitconfig`, vi-mode everywhere
- **dwl** — bar/movestack/pertag/warpcursor patches on top of upstream dwl
  (fork: [dwl](https://github.com/mellen9999/dwl)); `dwl-config.h` here is the
  config, symlinked into the fork's `config.h` at build time
- **foot / mako / btop / mpv** — terminal, notifications, monitor, player configs
- **pipewire** — a gaming quantum pin (fixes audio glitches under load)
- **ananicy** — scheduling priorities so background work never outranks a game
- **chromium** — privacy policy (no history sync, no password/autofill leak,
  no metrics) + a square/flat mono theme
- **vivaldi** — a script that patches the live profile for the same
  square/flat/private setup, plus the css that does it
- **claude code** — settings, hooks (edit backups, destructive-command guard,
  context nudges), skills, and a selfcheck suite that actually *executes* every
  hook against a synthetic payload instead of assuming it still works
- **cw** — git worktree tooling so multiple claude sessions can run against one
  repo without clobbering each other
- **leakcheck / pii-scan** — a pre-commit gate + on-demand audit that blocks
  secrets and personal info before they ever hit git history

## install

```
git clone https://github.com/mellen9999/dots ~/sync/config
~/sync/config/link.sh        # symlinks everything into place
~/sync/config/link.sh -n     # dry run first if you want to see what it'll do
```

`link.conf` drives it — one `source:target[:hostname]` line per entry. entries
whose source isn't present in this repo (machine-specific stuff that stayed
private) are skipped, not errors.

## notes

- a few configs (`chromium-flags.conf`, the chromium privacy policy) carry
  `$HOME` as a placeholder for a path — chromium doesn't expand env vars in
  policy files, so swap in your real home directory there.
- machine-specific infra (backup jobs, NAS sync, router scripts, business
  tooling) lives in a private repo and isn't part of this one.

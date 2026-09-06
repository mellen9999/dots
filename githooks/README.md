# global git hooks

shared pre-commit that runs [gitleaks](https://github.com/gitleaks/gitleaks) on
the staged diff and blocks any commit that would introduce a secret. lives in
the dotfiles repo so both machines get it on pull.

## wiring

set once per machine (already in the synced `.gitconfig`):

```
git config --global core.hooksPath ~/sync/config/githooks
```

## requirement

gitleaks must be on `PATH`. binary install, no sudo:

```
ver=8.30.1
curl -sSL "https://github.com/gitleaks/gitleaks/releases/download/v${ver}/gitleaks_${ver}_linux_x64.tar.gz" \
  | tar xz -C /tmp gitleaks && install -m755 /tmp/gitleaks ~/.local/bin/gitleaks
```

if gitleaks is missing the hook warns (loud) and allows the commit — install it.

## notes

- repos with their own `core.hooksPath` (e.g. `heatsync/.githooks`) bypass this
  one and call gitleaks themselves.
- the hook also chains to a repo's `.git/hooks/pre-commit` if present.
- deliberate override for a known-safe commit: `git commit --no-verify`.

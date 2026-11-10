---
name: sync-config
description: Commit and push changes to the ~/sync/config dotfiles repo. Only on explicit /sync-config.
allowed-tools: Bash
model: haiku
---

# sync-config

~/.claude is a symlink into this repo, so there is no mirror step.

1. `cd ~/sync/config && git status --short` — if clean, report and exit
2. never touch files you didn't change (other sessions may have them dirty). stage explicit paths only: `git add -- <path> ...`. never `git add -A` / `git add .`
3. `gitleaks git --staged --no-banner` — any finding stops everything
4. terse conventional lowercase commit message from the staged files: `git commit -m "..."`, then `git push`
5. report what was committed

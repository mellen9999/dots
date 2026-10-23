---
name: sync-config
description: Commit and push changes to ~/sync/config dotfiles repo
allowed-tools: Bash
model: haiku
---

# Sync Config

1. `cd ~/sync/config && claude-mirror && git status --short` (mirror backs up ~/.claude first; a gate failure stops everything)
2. If clean, report and exit.
3. `git add -A`
4. Generate terse conventional commit message from changed files.
5. `git commit -m "MESSAGE" && git push`
6. Report what was committed.

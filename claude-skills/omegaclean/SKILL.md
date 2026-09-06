---
name: omegaclean
description: Weekly cleanup of claude state, caches, and stale files. Reaps merged `cw` worktrees + orphaned conversation transcripts, prunes file-history/paste/debug/session-env caches, truncates runaway logs, removes sync-conflict dupes, vacuums local sqlite dbs. Reports reclaimed space per source.
allowed-tools: Bash
model: haiku
---

# omegaclean

Weekly maintenance sweep. Safe by default — only removes files older than the configured age, and never touches `memory/` subdirs under `~/.claude/projects/<project>/`.

## Steps

1. Capture starting sizes (one report covers all of these):
   - `du -sh ~/.claude/ /tmp/claude-* 2>/dev/null`
   - Per-subdir baseline: `du -sh ~/.claude/projects ~/.claude/file-history ~/.claude/paste-cache ~/.claude/backups 2>/dev/null`

2. Remove stale state files (always safe; rm/find no-ops if missing):
   - `rm -f ~/.claude/security_warnings_state_*.json`
   - `rm -f ~/.claude/.credentials.sync-conflict-*`
   - `rm -f ~/.claude/session-log.sync-conflict-*`
   - `find ~/ -name "*.sync-conflict-*" -mtime +7 -delete 2>/dev/null`

3. Prune caches by age:
   - `find ~/.claude/file-history -mindepth 1 -mtime +14 -delete 2>/dev/null` (was 30d — file-history hits 600MB+ fast)
   - `find ~/.claude/debug -mindepth 1 -mtime +30 -delete 2>/dev/null`
   - `find ~/.claude/paste-cache -mindepth 1 -mtime +7 -delete 2>/dev/null`
   - `find ~/.claude/session-env -mindepth 1 -mtime +30 -delete 2>/dev/null`
   - `find ~/.claude/backups -mindepth 1 -mtime +14 -delete 2>/dev/null`
   - `find /tmp/claude-* -mindepth 1 -mtime +7 -delete 2>/dev/null` (agent task outputs)
   - `find ~/.local/state/heatsync-alerts/runs ~/.local/state/heatsync-triage/runs -type f -mtime +14 -delete 2>/dev/null` (instafix/triage run logs; pollers also prune — belt-and-braces)

4. Reap stale robot windows in tmux session `hq` (heatpc only; instafix/triage runs self-destroy — this catches hung strays). TERM the pane's process group, NOT `tmux kill-window` alone: kill-window's HUP only reaches the shell, which defers its cleanup trap while claude runs, orphaning the tree. Skip window `hq` (dashboard). Report count reaped.
   - Age via `ps -o etimes=` on the pane pid — tmux has NO pane-creation-time format (an empty format var reads as 0 in arithmetic and reaps everything):
   - `tmux list-panes -s -t =hq -F '#{window_id} #{window_name} #{pane_pid}' 2>/dev/null | while read -r wid name pid; do [ "$name" = hq ] && continue; age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' '); [ -n "$age" ] && [ "$age" -gt 2700 ] && { kill -TERM -- "-$pid" 2>/dev/null; sleep 2; tmux kill-window -t "$wid" 2>/dev/null; echo "reaped $name"; }; done`

5. Reap merged `cw` worktrees across known repos. `cw-clean` is safe-by-construction — only reaps `claude/*` branches whose tip is fully merged into `origin/main`; never touches the current worktree, locked worktrees, or branches with unlanded commits.
   - `for repo in ~/projects/heatsync-extension ~/projects/heatsync ~/projects/cmdchamp; do [ -d "$repo/.worktrees" ] && (cd "$repo" && cw-clean 2>&1 | sed "s|^|[$(basename $repo)] |"); done`

6. Reap orphaned worktree conversation dirs (>7d unmodified). Each `cw` worktree gets a `~/.claude/projects/<encoded-path>/` convo dir for transcripts; when the worktree is reaped the convo dir is orphaned. 7d window protects any active session.
   - `find ~/.claude/projects/ -maxdepth 1 -name "*worktrees*" -mtime +7 -type d -exec rm -rf {} + 2>/dev/null`

7. Prune old conversation transcripts in main project dirs (>60d). Never touches `memory/` subdirs (those are persistent auto-memory and must survive).
   - `find ~/.claude/projects/ -maxdepth 2 -name "*.jsonl" -mtime +60 -delete 2>/dev/null`
   - `find ~/.claude/projects/ -maxdepth 2 -type d -name "[0-9a-f][0-9a-f]*-*-*-*-*" -mtime +60 -empty -delete 2>/dev/null` (companion empty UUID dirs)

8. Truncate runaway logs (current claude code writes `history.jsonl`; old `session-log.txt` path kept as no-op for older installs):
   - If `~/.claude/history.jsonl` >10MB, keep last 5000 lines
   - If `~/.claude/session-log.txt` >10MB (older installs), keep last 1000 lines

9. Vacuum local sqlite dbs (best-effort, ignore missing):
   - `for db in ~/.bazaarinfo.db ~/projects/bazaarinfo/bazaar.db; do [ -f "$db" ] && sqlite3 "$db" 'VACUUM' 2>/dev/null; done`

10. Capture ending sizes (same scope as step 1) and write timestamp to `~/.claude/.last-cleanup`.

## Report shape
- Before/after total size of `~/.claude/` + reclaimed MB
- Per-subdir reclaim breakdown (projects/, file-history/, paste-cache/, backups/) — surfaces which step won most
- Worktrees reaped (count per repo)
- Anything skipped or errored
- Warn if any single subdir is still >500MB after cleanup (signals retention may need to drop further)

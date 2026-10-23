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
   - `find ~ -maxdepth 1 -name '.claude.json.tmp.*' -mtime +1 -delete` (abandoned atomic-write temps, ~150K each)

3. Prune caches by age:
   - `find ~/.claude/file-history -mindepth 1 -mtime +14 -delete 2>/dev/null` (was 30d — file-history hits 600MB+ fast)
   - `find ~/.claude/debug -mindepth 1 -mtime +30 -delete 2>/dev/null`
   - `find ~/.claude/paste-cache -mindepth 1 -mtime +7 -delete 2>/dev/null`
   - `find ~/.claude/session-env -mindepth 1 -mtime +30 -delete 2>/dev/null`
   - `find ~/.claude/backups -mindepth 1 -mtime +14 -delete 2>/dev/null`
   - orphaned file-history (session id with no transcript anywhere, >1d old): `for d in $(find ~/.claude/file-history -mindepth 1 -maxdepth 1 -type d -mtime +1); do id=$(basename "$d"); ls ~/.claude/projects/*/"$id".jsonl >/dev/null 2>&1 || rm -rf "$d"; done` (158 dirs / 94M found sep 6 2026)
   - `find ~/.claude/session-env ~/.claude/tasks ~/.claude/file-history -mindepth 1 -type d -empty -delete 2>/dev/null` (1976 empty dirs found sep 6 2026 — pure scan overhead)
   - `find /tmp/claude-* -mindepth 1 -mtime +7 -delete 2>/dev/null` (agent task outputs)
   - `find ~/.local/state/heatsync-alerts/runs ~/.local/state/heatsync-triage/runs -type f -mtime +14 -delete 2>/dev/null` (instafix/triage run logs; pollers also prune — belt-and-braces)

4. Reap stale robot windows in tmux session `hq` (heatpc only; instafix/triage runs self-destroy — this catches hung strays). TERM the pane's process group, NOT `tmux kill-window` alone: kill-window's HUP only reaches the shell, which defers its cleanup trap while claude runs, orphaning the tree. Skip window `hq` (dashboard). Report count reaped.
   - Age via `ps -o etimes=` on the pane pid — tmux has NO pane-creation-time format (an empty format var reads as 0 in arithmetic and reaps everything):
   - `tmux list-panes -s -t =hq -F '#{window_id} #{window_name} #{pane_pid}' 2>/dev/null | while read -r wid name pid; do [ "$name" = hq ] && continue; age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' '); [ -n "$age" ] && [ "$age" -gt 2700 ] && { kill -TERM -- "-$pid" 2>/dev/null; sleep 2; tmux kill-window -t "$wid" 2>/dev/null; echo "reaped $name"; }; done`

5. Reap merged `cw` worktrees across known repos. `cw-clean` is safe-by-construction — only reaps `claude/*` branches whose tip is fully merged into `origin/main`; never touches the current worktree, locked worktrees, or branches with unlanded commits.
   - `for repo in ~/projects/heatsync-extension ~/projects/heatsync ~/projects/heatsync-tui ~/projects/cmdchamp ~/projects/xos ~/projects/bazaarinfo; do [ -d "$repo/.worktrees" ] && (cd "$repo" && cw-clean 2>&1 | sed "s|^|[$(basename $repo)] |"); done`

5b. Reap rust `target/` dirs inside worktrees that survived cw-clean but sat idle >7d (2.6G + 1.6G found sep 6 2026; a rebuild is cheap, the dir is not):
   - `find ~/projects -maxdepth 6 -type d -name target -path '*worktrees*' -mtime +7 -prune -exec rm -rf {} + 2>/dev/null`

5c. Reap merged+clean agent worktrees under `.claude/worktrees/` (cw-clean never sees these — registered by path, branches are `worktree-*` not `claude/*`). Gates: registered in `git worktree list`, branch merged into default and not the default itself, clean status, dir mtime >24h, no process cwd inside (sessions run concurrently). 18 found sep 6 2026 = 4.4G.
   - `for repo in ~/projects/heatsync ~/projects/heatsync-extension ~/projects/bazaarinfo; do [ -d "$repo/.claude/worktrees" ] || continue; cd "$repo"; def=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | cut -d/ -f2); def=${def:-main}; now=$(date +%s); for w in .claude/worktrees/*/; do r=$(realpath "$w"); git worktree list --porcelain | grep -qx "worktree $r" || continue; b=$(git -C "$w" branch --show-current 2>/dev/null); [ -n "$b" ] && [ "$b" != "$def" ] || continue; git merge-base --is-ancestor "$b" "$def" || continue; [ -z "$(git -C "$w" status --porcelain)" ] || continue; [ $(( (now - $(stat -c %Y "$w")) / 3600 )) -gt 24 ] || continue; ls -l /proc/[0-9]*/cwd 2>/dev/null | grep -q "$r" && continue; git worktree remove --force "$w" && git branch -D "$b" >/dev/null && echo "[$(basename $repo)] reaped $b"; done; done`

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

10. Host-level caches (skip any step whose tool is missing; `sudo -n` failure = skip and say so):
   - `docker volume ls -qf dangling=true | wc -l` then `docker volume prune -f` — heatsync CI leaves ~100 orphan volumes/day on heatpc (1863 = 53GB found sep 6 2026); dangling-only, running containers untouched
   - `sudo -n paccache -rk2; true` — pacman cache (9.9GB → 7.9GB on heatpc; 18GB on mele); `;` not `&&`, paccache exits 1 when nothing to trim
   - `rm -rf ~/.cache/paru/clone/*` unless `pgrep makepkg` — 6.8GB of stale AUR clones found sep 6 2026
   - `sudo -n find /var/cache/pacman/pkg -maxdepth 1 -name 'download-*' -type d -exec rm -rf {} +` — root-owned partial downloads paccache can't see (66 on heatpc, 60 on mele)
   - `sudo -n journalctl --vacuum-size=500M` — journald.conf.d caps it at 500M going forward; this catches pre-cap archives
   - `sudo -n find /var/lib/systemd/coredump -type f -mtime +14 -delete` — crash-hunt dumps stay 2 weeks (25 dumps = 2.3G found sep 6 2026)
   - `docker image prune -f` — dangling CI images (452MB found sep 6 2026)
   - `rm -rf ~/.bun/install/cache` — `bun pm cache rm` does NOT clear it (2.4GB found sep 6 2026)
   - CI runner (heatpc): `find ~/actions-runner-heatsync/_diag -name '*.log' -mtime +7 -delete` (~40M/day, no built-in retention); `[ -f ~/actions-runner-heatsync/_work/_update/update.finished ] && rm -rf ~/actions-runner-heatsync/_work/_update` (finished self-update staging, 670M found sep 6 2026); `pgrep -f Runner.Worker >/dev/null || git -C ~/actions-runner-heatsync/_work/heatsync/heatsync gc -q --prune=now` (every CI fetch leaves a near-full pack: 276 packs / 2.1G found sep 6 2026)
   - `hardlink --reflink=always -q -s 100K ~/data ~/downloads` — btrfs reflink dedupe, names + inodes untouched, idempotent (1.28G found sep 6 2026)
   - mele, one job at a time (8GB, passive): `ssh -o ConnectTimeout=8 mele 'sudo -n paccache -rk1; sudo -n find /var/cache/pacman/pkg -maxdepth 1 -name "download-*" -type d -exec rm -rf {} +; find ~/.claude -name "*.sync-conflict-*" -delete'`
10b. Gate — transcript sync must stay off. `find ~/.claude -name '*.sync-conflict-*' | wc -l` must be 0 on heatpc AND mele after step 2; if not, `.stignore` in `~/sync/config` has regressed on one box (syncthing never syncs `.stignore` itself — it travels via git, `scp` it if the boxes disagree). Say so loudly in the report.

11. Capture ending sizes (same scope as step 1) and write timestamp to `~/.claude/.last-cleanup`.

## Report shape
- Before/after total size of `~/.claude/` + reclaimed MB
- Per-subdir reclaim breakdown (projects/, file-history/, paste-cache/, backups/) — surfaces which step won most
- Worktrees reaped (count per repo)
- Anything skipped or errored
- Warn if any single subdir is still >500MB after cleanup (signals retention may need to drop further)

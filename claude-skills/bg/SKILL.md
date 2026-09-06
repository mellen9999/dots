---
name: bg
description: Spawn a background Claude in a dedicated `bg` tmux session to run a long task in parallel. Use when the current pane would block on a slow task (audit, log scan, soak test, large search).
allowed-tools: Bash
model: haiku
---

# bg — Background Claude

Spawn a parallel Claude in the dedicated `bg` session with $ARGUMENTS as the prompt.
Keeps background work out of the working session so `b-w` stays legible.

## Steps

1. Detect current tmux session:
   ```bash
   SESS=$(tmux display-message -p '#S' 2>/dev/null)
   [ -z "$SESS" ] && { echo "Not in tmux. Start a tmux session first."; exit 1; }
   ```

2. Generate the window name — readable, not a timestamp. `cw-name` takes a
   prefix and the prompt, and returns e.g. `bg-nginx`, unique against open tabs:
   ```bash
   NAME=$(cw-name bg "$ARGUMENTS")
   ```

3. Spawn into the `bg` session, creating it if absent. `remain-on-exit failed`
   means a job that succeeds closes its window and the session reaps itself,
   while a job that dies stays on screen instead of vanishing. It is set from
   *inside* the window before the job starts — setting it from out here loses
   the race against a job that fails instantly, which is the case that matters.
   ```bash
   CMD="tmux set-option -w remain-on-exit failed; claude --print '$ARGUMENTS' | tee /tmp/claude-bg-$NAME.log"
   if tmux has-session -t bg 2>/dev/null; then
     tmux new-window -d -t bg: -n "$NAME" "$CMD"
   else
     tmux new-session -d -s bg -n "$NAME" "$CMD"
   fi
   ```

4. Report:
   - New window name
   - How to reach it: `tmux switch-client -t bg:$NAME` (or `b-s`)
   - Where output is logged: `/tmp/claude-bg-$NAME.log`

## Rules
- NEVER steal focus — `-d` keeps the current session/window active
- The `bg` session dies on its own when its last job exits — never add a placeholder window
- A failed job leaves a dead window behind on purpose. Read it, then `b-&` to close;
  never set `remain-on-exit off` to tidy it away — silent failure is the bug it prevents
- Quote $ARGUMENTS carefully — escape any embedded quotes
- If $ARGUMENTS is empty, error out with usage

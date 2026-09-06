Prove the claude code setup on this machine still works.

Run `sh ~/.claude/selfcheck/run.sh` and report the result.

It executes every hook with a synthetic payload in a sandbox and asserts on the
side effect, then validates agents, skills, mcp servers, the memory index, and
credential hygiene. Exit 0 means green.

For anything that FAILs, fix the cause — do not silence the check. Re-run until
green, then commit the fix (`~/.claude` is the git-tracked `sync/config/claude`).

`sh ~/.claude/selfcheck/faults.sh` tests the tester: it injects one known
breakage at a time and asserts the matching check goes red. Run it after adding
or editing a check — a check that cannot fail is decoration.

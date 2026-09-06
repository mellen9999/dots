---
name: audit
description: Run the 7-step pipeline (test, verify, permanent, harden, refactor, clean) on current repo
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent
model: sonnet
---

# Audit — 7-Step Pipeline

Run the full quality pipeline on the current repo. Accepts optional focus area as $ARGUMENTS (e.g., `/audit security`, `/audit performance`).

## Steps

1. **Test** — run the test suite (`bun test`), report failures
2. **Verify** — check the app actually works (start server, hit endpoints, check logs)
3. **Permanent** — find any one-off changes that should be persisted (systemd, config, cron)
4. **Harden** — security scan: input validation, XSS, injection, auth checks. Performance: redundant queries, missing indexes, unnecessary allocations
5. **Refactor** — identify files that are too large, misplaced logic, poor naming, architectural debt
6. **Clean** — dead code, unused imports, stale comments, leftover debug logs, TODO graveyard
7. **Report** — summary of findings + fixes applied

## Rules
- Fix obvious issues directly, don't just report them
- For ambiguous refactors, ask before restructuring
- Run tests again after any changes to confirm nothing broke

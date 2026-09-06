---
paths: ["**/migrations/**"]
---

# Database Migration Rules

- Never modify existing migration files — create new ones only
- Migration filenames: next sequential number, descriptive name
- Always include both up and down logic where possible
- Test migrations against a copy before applying to prod
- HeatSync: numbered SQL files, run via `bun run db:migrate`
- BazaarInfo: inline migrations in `db.ts` — add new ALTER TABLE blocks to `initDb()`

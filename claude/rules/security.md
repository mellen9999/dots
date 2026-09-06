---
paths: ["**/routes/**", "**/middleware/**", "**/security/**", "**/auth*"]
---

# Security Rules for Route/Auth Code

- All user input must be validated with Zod schemas before use
- SQL: always use parameterized queries (template literals with postgres.js, `?` with bun:sqlite)
- Never trust client-side auth state — verify JWT server-side on every request
- CSRF tokens required on all non-GET mutations
- Sanitize HTML output with DOMPurify before rendering
- Rate limit all public endpoints via Redis
- CSP nonces: never use `unsafe-inline`, always inject per-request nonce

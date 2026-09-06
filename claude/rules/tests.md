---
paths: ["**/tests/**", "**/*.test.*", "**/*.spec.*"]
---

# Test Rules

- Tests must hit real databases, never mock DB layers
- Each test file should be independently runnable
- No test should depend on execution order of other test files
- Clean up test data after each test (use beforeEach/afterEach)
- Prefer testing behavior over implementation details
- E2E tests: use data-testid attributes, never CSS selectors that break on style changes

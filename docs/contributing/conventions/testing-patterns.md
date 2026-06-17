# Testing Patterns

Deep how-to: [../../guides/testing.md](../../guides/testing.md), [../../guides/e2e-testing.md](../../guides/e2e-testing.md).

## Execution

```bash
cd server && bundle exec rspec --format progress     # Full suite
cd server && bundle exec rspec spec/path_spec.rb     # Single file
cd server && bundle exec rspec spec/path_spec.rb:42  # Single example
cd frontend && CI=true npm test                      # Frontend (always CI=true)
```

## Multi-Agent Test Rules

- Uses `DatabaseCleaner` with `:deletion` strategy — avoids `TRUNCATE` deadlocks between concurrent processes.
- Do NOT run multiple single-process rspec instances simultaneously on the same database.
- Frontend tests (`CI=true npm test`) and TypeScript checks (`npx tsc --noEmit`) are always safe to run concurrently.

## Patterns Reference

| Pattern | Rule |
|---------|------|
| Factories | `spec/factories/` — use existing factories with traits (`:active`, `:paused`, `:archived`). AI factories in `spec/factories/ai/` |
| User Setup | `user_with_permissions('perm.name')` from `permission_test_helpers.rb` — never create users manually |
| Auth Headers | `auth_headers_for(user)` returns `{ Authorization: Bearer ... }` — use in all request specs |
| Response Helpers | `json_response`, `json_response_data`, `expect_success_response(data)`, `expect_error_response(msg, status)` |
| Shared Examples | `include_examples 'requires authentication'`, `'requires permission'`, `'scopes to current account'` — see `spec/support/shared_examples/` |
| AI Matchers | `be_a_valid_ai_response`, `have_execution_status(:status)`, `create_audit_log(:action)` — see `spec/support/ai_matchers.rb` |
| AI Helpers | `ProviderHelpers`, `AgentHelpers`, `WorkflowHelpers`, `SecurityHelpers` — see `spec/support/ai_test_helpers.rb` |
| E2E Pages | Page objects in `e2e/pages/` — always reuse; check `e2e/pages/ai/` for AI features |
| E2E Selectors | `data-testid` first, then `class*="pattern"`, then `getByRole` — add `data-testid` to new components |
| E2E Guards | `page.on('pageerror', () => {})` in beforeEach, `if (await el.count() > 0)` for optional elements |

## Test-First Bug Reproduction

For bug fixes, write a failing test that reproduces the bug BEFORE the fix — confirms the bug exists, prevents regression, forces root-cause understanding.

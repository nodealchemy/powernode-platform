## Summary

Brief description of what this PR does and why.

## Related Issues

Closes #
Refs #

## Type of Change

- [ ] Bug fix (non-breaking)
- [ ] New feature (non-breaking)
- [ ] Breaking change (existing behavior changes)
- [ ] Documentation update
- [ ] Refactor / cleanup (no functional change)
- [ ] Test coverage improvement
- [ ] Tooling / CI / scripts

## Testing

How was this verified?

- [ ] Backend specs added/updated: `cd server && bundle exec rspec spec/path/to/spec.rb`
- [ ] Frontend tests added/updated: `cd frontend && CI=true npm test -- path/to/test`
- [ ] E2E tests added/updated (`e2e/`)
- [ ] Manual verification — describe steps below

```
Paste relevant test output or manual verification steps here.
```

## Pre-Merge Checklist

- [ ] `./scripts/validate.sh` passes (or `--skip-tests` for incremental work)
- [ ] TypeScript clean: `cd frontend && npx tsc --noEmit`
- [ ] Conventions followed (see [`CLAUDE.md`](../CLAUDE.md)):
  - [ ] Frontend uses `currentUser?.permissions?.includes()` — never roles
  - [ ] Theme classes only (`bg-theme-*`, `text-theme-*`) — no hardcoded colors
  - [ ] `render_success()` / `render_error()` for API responses
  - [ ] `# frozen_string_literal: true` on new `.rb` files
  - [ ] No `console.log` in production code — use `logger` from `@/shared/utils/logger`
  - [ ] No `any` in TypeScript
- [ ] Migrations: `t.references` automatically creates the index — no separate `add_index` for FK columns
- [ ] Commit messages follow `type(scope): subject` format
- [ ] No AI-assistant attribution in commits (no `Co-Authored-By: Claude`, etc.)
- [ ] Documentation updated where applicable (`docs/`, `CLAUDE.md`, `README.md`)
- [ ] No secrets, credentials, fixtures with real customer data, or internal hostnames committed

## Screenshots / Demos (if UI change)

<!-- Drag images or short video here -->

## Notes for Reviewers

Anything specific to look for? Trade-offs you considered? Areas of uncertainty?

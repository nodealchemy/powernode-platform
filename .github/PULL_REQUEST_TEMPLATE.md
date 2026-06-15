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

## Affected Subsystem & Tier

Which area does this touch, and what stability tier is it? See
[`docs/STABILITY.md`](../docs/STABILITY.md). Breaking changes in Stable areas need a
deprecation path; Beta/Experimental have more latitude.

- Subsystem / component:
- Tier: `tier:stable` / `tier:beta` / `tier:experimental`

## Testing

How was this verified?

- [ ] Backend specs added/updated: `cd server && bundle exec rspec spec/path/to/spec.rb`
- [ ] Frontend tests added/updated: `cd frontend && CI=true npm test -- path/to/test`
- [ ] E2E tests added/updated (`e2e/`)
- [ ] Manual verification — describe steps below

```
Paste relevant test output or manual verification steps here.
```

## Checklist

- [ ] Tests pass (`./scripts/validate.sh`, or `--skip-tests` for incremental work) and TypeScript is clean (`cd frontend && npx tsc --noEmit`)
- [ ] Access control uses the **permission system**, not roles (`currentUser?.permissions?.includes()` on the frontend, `current_user.has_permission?('name')` on the backend)
- [ ] Frontend uses **theme classes** (`bg-theme-*`, `text-theme-*`) — no hardcoded colors
- [ ] Backend uses `render_success()` / `render_error()`; new `.rb` files have `# frozen_string_literal: true`; no `console.log` or `any` in TypeScript
- [ ] Migrations rely on `t.references` for FK indexes (no separate `add_index`)
- [ ] Commit messages follow `type(scope): subject`, with no AI-assistant attribution
- [ ] Documentation updated where applicable (`docs/`, `README.md`)
- [ ] No secrets, credentials, real customer data, or internal hostnames committed
- [ ] I have read the contribution terms in [`CONTRIBUTING.md`](../CONTRIBUTING.md)

## Screenshots / Demos (if UI change)

<!-- Drag images or short video here -->

## Notes for Reviewers

Anything specific to look for? Trade-offs you considered? Areas of uncertainty?

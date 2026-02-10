---
name: fix-tests
description: Run tests, diagnose failures, fix and re-run until green
disable-model-invocation: true
argument-hint: [scope: backend|frontend|e2e|path/to/spec]
---

# Fix Tests Workflow

Run the test suite for the given scope, diagnose failures, fix them, and re-run. Follow this process exactly:

## Step 1: Determine Scope

Parse the argument to determine what to run:
- `backend` or no argument → `cd server && bundle exec rspec --format progress`
- `frontend` → `cd frontend && CI=true npm test`
- `e2e` → `cd frontend && npx playwright test`
- A specific file path → run that file directly

## Step 2: Run Tests

Execute the test command and capture output. Note all failures.

## Step 3: Fix Loop (max 3 attempts per failure)

For each failing test:

1. **Read** the failing spec file and the source file it tests
2. **Diagnose** the root cause — check for:
   - Missing factory traits (check `spec/factories/` and `spec/factories/ai/`)
   - Wrong test helpers (use `user_with_permissions`, `auth_headers_for`, `json_response`)
   - Missing shared examples (`spec/support/shared_examples/`)
   - Missing mocks or stubs for external services
   - Stale selectors in E2E tests (prefer `data-testid`)
   - Import path issues (use `@/shared/`, `@/features/`)
3. **Fix** the issue using Edit
4. **Re-run** just the failing file to verify the fix
5. If still failing after 3 attempts on the same test, **stop and report** — do not keep iterating

## Step 4: TypeScript Check (frontend/e2e only)

If any TypeScript files were modified:

```bash
cd frontend && npx tsc --noEmit
```

Fix any type errors found (same 3-attempt limit).

## Step 5: Final Run

Re-run the full suite for the original scope to confirm everything passes.

## Step 6: Summary

Report:
- Total tests: pass / fail / pending
- Failures fixed (list each with one-line description of what was wrong)
- Failures remaining (if any, with diagnosis of why they couldn't be auto-fixed)

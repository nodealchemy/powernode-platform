---
name: verify
description: Run targeted verification based on what changed since last commit
disable-model-invocation: true
argument-hint: [scope: auto|ruby|typescript|migration|seed|all]
---

# /verify — Targeted Change Verification

Run focused quality checks based on what actually changed. Faster than `validate.sh`, more thorough than hooks.

## Step 1: Detect Changes

If scope is `auto` or no argument provided, detect what changed:

```bash
# Changed Ruby files (unstaged + staged + untracked)
git diff --name-only HEAD -- '*.rb' 2>/dev/null
git diff --cached --name-only -- '*.rb' 2>/dev/null
git ls-files --others --exclude-standard -- '*.rb' 2>/dev/null

# Changed TypeScript files
git diff --name-only HEAD -- '*.ts' '*.tsx' 2>/dev/null
git diff --cached --name-only -- '*.ts' '*.tsx' 2>/dev/null
git ls-files --others --exclude-standard -- '*.ts' '*.tsx' 2>/dev/null

# Changed migrations and seeds
git diff --name-only HEAD -- 'server/db/migrate/' 2>/dev/null
git diff --name-only HEAD -- 'server/db/seeds/' 2>/dev/null
```

If a specific scope is given (`ruby`, `typescript`, `migration`, `seed`), only run that category.

## Step 2: Ruby Verification (if .rb files changed)

1. **Syntax check** all changed `.rb` files:
   ```bash
   ruby -c <file>  # for each changed file
   ```
2. **Find related specs**: Map each changed source file to its spec:
   - `app/models/foo.rb` → `spec/models/foo_spec.rb`
   - `app/services/foo.rb` → `spec/services/foo_spec.rb`
   - `app/controllers/api/v1/foo_controller.rb` → `spec/requests/api/v1/foo_spec.rb` or `foo_controller_spec.rb`
3. **Run related specs** (only those that exist):
   ```bash
   cd server && bundle exec rspec <spec-files> --format progress
   ```

## Step 3: TypeScript Verification (if .ts/.tsx files changed)

1. **Type check** the full frontend project:
   ```bash
   cd frontend && npx tsc --noEmit
   ```
2. **Find related tests**: Look for `*.test.ts` or `*.test.tsx` alongside changed files
3. **Run related tests** (if they exist):
   ```bash
   cd frontend && CI=true npx react-scripts test --testPathPattern="<pattern>" --watchAll=false
   ```

## Step 4: Migration Verification (if migration files changed)

1. **Check migration status**:
   ```bash
   cd server && bundle exec rails db:migrate:status
   ```
2. If any migrations are `down`, run them:
   ```bash
   cd server && bundle exec rails db:migrate
   ```

## Step 5: Seed Verification (if seed files changed)

1. **Run seeds**:
   ```bash
   cd server && bundle exec rails db:seed
   ```
2. Report success or failure with specific error context.

## Step 6: Report

Present results as a summary table:

```
| Category    | Status    | Details              |
|-------------|-----------|----------------------|
| Ruby syntax | PASS/FAIL | N files checked      |
| Ruby specs  | PASS/FAIL/SKIP | N specs, M failures |
| TypeScript  | PASS/FAIL | N errors             |
| TS tests    | PASS/FAIL/SKIP | N tests run     |
| Migrations  | PASS/FAIL/N/A  | N pending       |
| Seeds       | PASS/FAIL/N/A  | status          |
```

If all pass: "Safe to commit."
If any fail: List specific failures with file paths and error messages.

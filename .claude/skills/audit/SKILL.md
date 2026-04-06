---
name: audit
description: Run comprehensive codebase quality and pattern compliance audit
disable-model-invocation: true
allowed-tools: Bash(./scripts/*), Bash(cd *), Bash(npx *), Bash(bundle *), Bash(git *), Read, Grep, Glob
argument-hint: [focus: all|backend|frontend|types|patterns]
---

# Codebase Quality Audit

Run quality checks and report results. Accept an optional focus argument to limit scope.

## Focus Areas

- **all** (default) — run everything
- **backend** — Ruby checks only (steps 1, 4, 5, 6)
- **frontend** — Frontend checks only (steps 3, 7, 8)
- **types** — TypeScript type check only (step 3)
- **patterns** — Pattern validation only (steps 1, 2)

## Checks

Run applicable checks sequentially. Capture output from each.

### 1. Pattern Validation
```bash
cd $PROJECT_DIR && ./scripts/pattern-validation.sh
```

### 2. Quick Pattern Check
```bash
cd $PROJECT_DIR && ./scripts/quick-pattern-check.sh
```

### 3. TypeScript Type Check
```bash
cd $PROJECT_DIR/frontend && npx tsc --noEmit 2>&1
```

### 4. Ruby Syntax Check
Check all `.rb` files changed since last commit:
```bash
cd $PROJECT_DIR/server && git diff --name-only HEAD -- '*.rb' | xargs -I{} ruby -c {} 2>&1
```
Also check untracked `.rb` files:
```bash
cd $PROJECT_DIR/server && git ls-files --others --exclude-standard -- '*.rb' | xargs -I{} ruby -c {} 2>&1
```

### 5. Rails Eager Load Check (backend only)
Verify all Ruby classes load without errors:
```bash
cd $PROJECT_DIR/server && bundle exec rails runner "Rails.application.eager_load!; puts 'Eager load OK'" 2>&1
```

### 6. Frozen String Literal Pragma
Scan for Ruby files missing the pragma:
```bash
grep -rL "frozen_string_literal: true" $PROJECT_DIR/server/app/ --include="*.rb" | head -20
```

### 7. Console.log Scan
```bash
grep -rn "console\.log" $PROJECT_DIR/frontend/src/ --include="*.ts" --include="*.tsx" | head -20
```

### 8. Hardcoded Color Scan
```bash
grep -rn "bg-\(red\|blue\|green\|yellow\|gray\|slate\|zinc\|neutral\|stone\)" $PROJECT_DIR/frontend/src/ --include="*.tsx" | grep -v "theme" | head -20
```

## Output

Present results as a summary table:

```
| Check                  | Status | Issues |
|------------------------|--------|--------|
| Pattern Validation     | ✅/❌  | count  |
| Quick Pattern Check    | ✅/❌  | count  |
| TypeScript Types       | ✅/❌  | count  |
| Ruby Syntax            | ✅/❌  | count  |
| Rails Eager Load       | ✅/❌  | count  |
| Frozen String Literal  | ✅/❌  | count  |
| Console.log            | ✅/❌  | count  |
| Hardcoded Colors       | ✅/❌  | count  |
```

If any check has issues, list the specific files/errors below the table.

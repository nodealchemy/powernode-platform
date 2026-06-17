# Convention-Adherence Baseline

Captured before the CLAUDE.md rule migration, via `scripts/pattern-validation.sh`. This is the **regression gate** (A3): after migrating a rule out of always-loaded prose, its `pattern-validation.sh` check must not regress. If compliance drops or a "should be empty" check goes non-zero over subsequent sessions, that rule is promoted back to core/hook rather than left in doc/MCP.

## Baseline — 2026-06-16

```
Total Checks: 30
Passed: 27
Failed: 0
Warnings: 3
Compliance Rate: 90%
```

Known warnings at baseline (pre-existing, not introduced by this work):
- TypeScript `any` types: 347 found (expected ≤5) — now also nudged at edit-time by `no-any-type-check.sh`.
- (2 further warnings within the 3 total.)

Re-run: `scripts/pattern-validation.sh`. Compare Compliance Rate and the per-check PASS/FAIL/WARN lines against this baseline.

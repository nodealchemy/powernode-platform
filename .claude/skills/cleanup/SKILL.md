# /cleanup — Codebase Cleanup

Run codebase cleanup and validation scripts. Wraps existing automation scripts into a single command.

## Usage

```
/cleanup              # Run all cleanup checks
/cleanup console      # Remove console.log statements
/cleanup patterns     # Run pattern validation audit
/cleanup colors       # Fix hardcoded color violations
/cleanup imports      # Convert relative imports to path aliases
/cleanup quick        # Quick pattern check only
```

## Workflow

### Determine Scope

Based on the argument (default: `all`), run the appropriate scripts:

| Argument | Script | Description |
|----------|--------|-------------|
| `all` | All scripts below in order | Full cleanup pass |
| `console` | `./scripts/cleanup-all-console-logs.sh` | Remove `console.log` from frontend |
| `patterns` | `./scripts/pattern-validation.sh` | Full pattern audit (colors, imports, types) |
| `colors` | `./scripts/fix-hardcoded-colors.sh` | Replace hardcoded colors with theme classes |
| `imports` | `./scripts/convert-relative-imports.sh` | Convert relative imports to `@/` aliases |
| `quick` | `./scripts/quick-pattern-check.sh` | Fast pattern check |

### Execution

1. Run the selected script(s) from the project root
2. Capture output and report results
3. If `all` mode, run in this order:
   1. `./scripts/cleanup-all-console-logs.sh`
   2. `./scripts/fix-hardcoded-colors.sh`
   3. `./scripts/convert-relative-imports.sh`
   4. `./scripts/pattern-validation.sh`
4. Report summary of changes made and any remaining issues

### Post-Cleanup Verification

After cleanup, run quality gates:
```bash
cd frontend && npx tsc --noEmit    # Verify no TypeScript errors introduced
```

If TypeScript errors are introduced by cleanup, fix them before reporting completion.

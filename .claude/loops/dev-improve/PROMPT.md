# Workload: dev-improve

Operator-approved code-quality improvements discovered via `/improve`. Each task is one
approved `Ai::ImprovementRecommendation` (`task.metadata.recommendation_id` back-links it),
seeded by `Ai::DevLoop::ImprovementPromotionService` on approval and drained via
`dev_next_task` / `dev_complete_task`. Loop-agnostic bridge — no special handling.

## Context
- `task.metadata.kind` ∈ {`code_lint`, `dead_code`, `code_duplication`, `convention_adherence`, `test_gap`}.
- `task.metadata.files` / `repository` / `verifier_evidence` describe the finding.
- Findings rot — ALWAYS re-verify the claim against current code before changing anything.
- MCP-first guidance recall (`search_knowledge tag:guidance-*`) MUST target the production
  connector (`mcp__powernode__*`). A sandbox/dev connector (e.g. `mcp__powernode-local__*`) can
  have an unseeded knowledge store — a zero-result answer there is expected, not informative,
  and is not evidence the guidance doesn't exist.

## Iteration (one task)
1. **Re-verify:** confirm the finding still holds on HEAD. For `dead_code`/`code_duplication`,
   prove zero live callers with `platform.code_blast_radius` BEFORE deleting/extracting.
   If it no longer holds, report `outcome=passed` with a summary that it is already resolved.
2. **Branch:** the loop branch (`dev-loop/dev-improve`). Submodule files commit inside the submodule first.
3. **Test-first:** write a failing spec reproducing the finding; confirm it is red.
4. **Fix:** minimal change tracing to `task.acceptance_criteria`. No scope creep, no placeholders.
5. **Review-before-counted (scrutiny gate):** run `/code-review` on the diff. Do NOT report
   `passed` on spec-green alone for auto-discovered work — the review verdict is the quality gate.
6. **Verify:** new spec green + nearest existing spec; `tsc --noEmit` if frontend touched.
7. **Commit** to the loop branch only — never develop/master, never push, no attribution.
8. **Report** via `dev_complete_task` with `check_results` (include the `/code-review` verdict) and a `learning`.

## Core-purity (gate #9)
- NEVER introduce a core→extension dependency or a private-extension name into a core file
  (the `core-purity-check.sh` hook blocks this at edit time).
- A finding tagged to a private extension (`task.metadata.extension`) is fixed INSIDE that
  extension's submodule and committed there — never by editing core to reference it.

## Stop conditions (report, then stop)
- 3 failed attempts on the same task → `outcome=failed` with what was tried.
- Fix needs a design decision → `outcome=blocked` with the decision laid out.
- `emergency_halt` at any point → stop immediately.

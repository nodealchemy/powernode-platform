# Workload: dev-audit-fleet-substrate

Burn-down of the 2026-06-09 fleet-substrate audit (verified findings backlog,
`~/.claude/plans/system-audit-findings-2026-06-09.md`). Tasks were seeded by
`Ai::DevLoop::AuditBacklogSeeder`; each task is one finding (`task_key` = finding ID).

## Context

- Findings were live-or-statically verified 2026-06-09 by an adversarial multi-agent
  audit, but the 6 S1 headline fixes landed afterwards (commits `289ea47a`, `3ff57fc5`,
  `c7f73cd2` and extension-side fixes) — **always re-verify the claim first**; some
  S2/S3 findings may have been fixed incidentally.
- Root failure pattern of this audit: **cross-repo contract drift** — the system
  extension extends parent enums/validations/dispatch the parent doesn't know about,
  and neither test suite catches it. When fixing such a finding, the spec you write
  should exercise the full cross-repo path (see learning
  "System extension's flagship agent-mission features fail at cross-repo contract boundaries").
- `task.metadata.kind` tells you what you're dealing with:
  - `bug` — behavioral defect; spec-first reproduction, then fix.
  - `gap` — missing wiring/enforcement; spec asserts the wired behavior.
  - `test-gap` — coverage hole; the deliverable IS the spec (must meaningfully
    exercise the mutation paths, not smoke-test).
  - `wip` / `polish` — judge scope from acceptance criteria.

## Repos & Verification

- Most findings touch `extensions/system/` (git submodule, dual-remote — commit inside
  it first, no pointer bumps mid-loop) and some `server/` (parent).
- Specs: parent → `server/spec/...`; extension → `extensions/system/server/spec/...`,
  both run from `server/` with `bundle exec rspec`.
- The live dev DB backs the running platform: never run mutating repro commands
  (`rails runner` mutations, approving/cancelling live records) outside specs.
- Concurrency findings (races): reproduce with deterministic interleaving in specs
  where feasible (e.g. lock assertions, state-machine guards); a spec asserting the
  guard exists beats a flaky timing test.

## Extra Guardrails (in addition to loop guardrails)

- Respect the system extension's existing patterns: AASM state machines, service
  `Result` structs (`ok?` vs `success?` — F-series findings exist precisely because
  of interface drift), `Ai::AutonomyGate` for gated mutations.
- A fix that requires a parent + extension change in lockstep is fine — that's the
  point of this backlog — but keep both diffs minimal and commit each repo separately.
- If a finding's fix requires a design decision the audit left open (e.g. anything
  touching the fleet act-arc / F3-01 territory), report `blocked` rather than picking.

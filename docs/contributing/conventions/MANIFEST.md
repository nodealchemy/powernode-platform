# CLAUDE.md Rule Migration Manifest

Every rule that lived in the 410-line root `CLAUDE.md` maps to **exactly one authoritative home** below. This is the lossless-migration gate: no rule may be orphaned, and the home determines how it is enforced/recalled (per the "route by trigger shape" principle).

**Homes:** `core` = stays in the slim CLAUDE.md (outage-safe); `hook` = `.claude/hooks/*.sh` (edit-time); `scan` = `scripts/pattern-validation.sh` (adherence metric); `doc` = a `conventions/*.md` reference recalled via MCP-first + the SessionStart digest; `knowledge` = a `guidance-*`-tagged platform knowledge entry (created via `create_knowledge`), recalled cross-executor via `search_knowledge` — it reaches non-Claude executors, unlike the Claude-only SessionStart digest.

## Cross-executor recall wiring

The `doc`/SessionStart digest is **Claude-only**. `knowledge`-home rules (`guidance-*` entries) are delivered to *every* executor — Grok/Codex/Gemini/etc. as well as Claude — through two model-agnostic seams that instruct the executor to run `search_knowledge tag:guidance-*` before implementing and honor applicable rules:

- **Loop guardrails** — the `guidance-*` recall line in `Ai::DevLoop::CampaignDriver::DEFAULT_GUARDRAILS`, `Ai::DevLoop::AuditBacklogSeeder::GUARDRAILS`, and `Ai::DevLoop::ImprovementPromotionService::GUARDRAILS`, delivered in the `dev_next_task` payload to loop-driven executors.
- **Agent baseline** — `Ai::Agent::BASE_GUARDRAILS`, prepended into every agent's system prompt (`build_system_prompt_with_profile`) regardless of model/executor.

## Core-purity assertion (gate #9)

No file in `docs/contributing/conventions/` and no `global`-scoped guidance knowledge entry may name a private extension (its `Namespace::`, `extensions/private/<name>` path, or import alias) or contain crypto/private-extension implementation specifics. Such guidance belongs in the extension's own docs or `CLAUDE.local.md`. Source-file enforcement is the blocking `core-purity-check.sh` hook, which derives the forbidden names dynamically from `extensions/private/*`.

## Mapping

| Rule (from old CLAUDE.md) | Home | Where | Enforcement |
|---|---|---|---|
| Project overview, core models, specialists | core | CLAUDE.md | — |
| Git rules (never commit unless asked, no attribution, branch/tag naming) | core | CLAUDE.md | — |
| Business submodule / core-mode note | core | CLAUDE.md | — |
| **Permission-based access control (permissions not roles)** | core+knowledge | CLAUDE.md + `guidance-permissions-not-roles` | `permission-not-roles-check.sh` (nudge) + `pattern-validation.sh` (scan) |
| Frontend: colors / theme classes | doc+hook | frontend-patterns.md | `hardcoded-color-check.sh` + scan |
| Frontend: no `any` | doc+hook | frontend-patterns.md | `no-any-type-check.sh` + scan |
| Frontend: no console.log | doc+hook | frontend-patterns.md | `console-log-check.sh` + scan |
| Frontend: flat nav | doc+scan | frontend-patterns.md | `pattern-validation.sh` |
| Frontend: actions/state/imports | doc | frontend-patterns.md | review |
| Backend: namespace `::`, FK prefix, JSON lambda default, t.references index, class_name+foreign_key | doc+hook | backend-patterns.md | `ruby-convention-check.sh` |
| Backend: frozen_string_literal | doc+hook | backend-patterns.md | `ruby-syntax-check.sh` + scan |
| Backend: render_success/error, Rails.logger, worker BaseJob | doc+scan | backend-patterns.md | `pattern-validation.sh` |
| Backend: controller size <300 | doc+hook | backend-patterns.md | `controller-size-check.sh` |
| **Backend: webhook 200/202 (never 500)** | core | CLAUDE.md | `webhook-500-check.sh` (nudge) |
| **Backend: eager loading (.includes)** | core | CLAUDE.md | `n-plus-one-check.sh` (nudge) |
| Backend: seeds, controllers Api::V1 | doc | backend-patterns.md | review |
| Cryptographic material safety (GENERIC principles) | core+knowledge | CLAUDE.md + `guidance-crypto-material-safety` + agent `BASE_GUARDRAILS` | review (private specifics → CLAUDE.local.md) |
| Design principles (Reuse First, Quality Gates, Stop&Ask, Surface Assumptions, Audit=report, Verify, Trace Changes, Plan Before Multi-File, etc.) | core | CLAUDE.md | — |
| Architecture principles (Pull Never Push, Extension Isolation, Service Boundaries) | core | CLAUDE.md | `core-purity-check.sh` (isolation) |
| Bulk operation safety | core | CLAUDE.md | — |
| Submodule safety | core | CLAUDE.md | `submodule-boundary-check.sh` |
| Terminology | core | CLAUDE.md | — |
| Worker architecture invariants (no jobs in server/, no sidekiq in server Gemfile) | core | CLAUDE.md | `pattern-validation.sh` |
| **Worker: AI-execution jobs MUST include `AiSuspensionCheckConcern` (kill-switch compliance)** | core+knowledge | worker/CLAUDE.md + `guidance-kill-switch-compliance` | `pattern-validation.sh` (via `scripts/checks/kill-switch-compliance-check.sh`) |
| Service management + operations reference | doc | service-and-ops.md | — |
| Automation scripts | doc | service-and-ops.md | — |
| Test execution + multi-agent rules + patterns | doc | testing-patterns.md | — |
| MCP-first workflow (4 phases) | doc | mcp-first-workflow.md | SessionStart digest |
| MCP tool catalog | pointer | reference/auto/mcp-tools.md | auto-generated |
| Knowledge quality lifecycle + tool evolution | doc | knowledge-lifecycle.md | — |
| File organization (NEVER save to root) | core | CLAUDE.md | — |
| Key platform documentation (fallback table) | core | CLAUDE.md | — |

_Verification:_ `wc -l CLAUDE.md` ≈ 150; no `conventions/*.md` references a private-extension namespace/alias/path (derive the name list from `extensions/private/*`); every row above resolves to an existing home.

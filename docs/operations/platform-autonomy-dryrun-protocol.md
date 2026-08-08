# Platform Autonomy Dry-Run Protocol

**Status**: v1 draft — commissioned 2026-08-08. Charter decisions locked by the operator (see §2).
**Owner surface**: `docs/operations/` (this doc) + the `dryrun` harness (§6).

A standardized, repeatable end-to-end test that drives **real platform agents through
real providers** to deploy composed infrastructure, while measuring — per operation —
whether the platform chose the right provider/model/effort, kept context lean, used the
right skills, and converted the run into learning. It is the first harness to join the
two halves that exist today: the 33 smoke seeds (real infrastructure, zero agents) and
the provisioning integration specs (real agent pipeline, stubbed LLM + providers).

## 1. Why live execution

The 2026-06-09 audit is the standing argument: the platform's most agent-centric
features read as fully wired in static review and were non-functional end-to-end
(mission gates that could never approve, missions that could never complete, an
act-arc with 928 permanently-pending approvals). Live execution through a real
provider found in minutes what review missed. This protocol makes that class of
check standardized and repeatable instead of heroic.

## 2. Charter (operator-locked, 2026-08-08)

| Decision | Value |
|---|---|
| Environment | **dev-cell** platform drives real provisioning; **ops-hub is never touched** |
| Provider | The existing `IPNode PVE` Proxmox provider (cluster: dna, rna, lna, fna — all verified online) |
| Scale | Composed stack ~3–4 VMs: node instance + template + module assignments + a container runtime (docker-engine), **placed across dna AND rna** |
| Cleanup | Auto-terminate everything on PASS (teardown is part of the test); retain on FAIL for forensics |
| LLM budget | Hard per-run ceiling, default **$5**, SiteSetting `ai.dryrun.budget_usd` (configurable per platform convention — never hardcoded) |
| Routing posture | **Report-first**: record + grade every routing decision; flip to enforcement after 2–3 baselines define normal |
| Approvals | Baseline run: operator approves `review_plan`/`handoff` live (approval UX is under test). Repeat runs: harness approves its own `dryrun-`-marked missions individually |

## 3. Measurement dimensions and their oracles

All oracles already exist as persisted records; the dry-run reads them, it does not
invent parallel bookkeeping.

| Dimension | Oracle | Where |
|---|---|---|
| Provider/model/effort appropriateness | `Ai::RoutingDecision` (tier, strategy, per-candidate scoring, est/actual/alternative cost, savings, latency, outcome) + `Ai::TaskComplexityAssessment` (complexity vs `recommended_tier` vs `actual_tier_used`) | written by `TaskTierResolver` / `RoutingAnalytics`; read via `Api::V1::Ai::ModelRouterAnalyticsController` (`escalations`, `escalations/rollup`, `escalations/benefit`) |
| Governance conformance | escalation-without-justification fails closed to baseline; effort-first substitution < `ESCALATE_OVER_EFFORT_SCORE = 0.60`; frontier admission = 5 simultaneous conditions | `docs/contributing/conventions/model-routing-governance.md` |
| Cost | `Ai::AgentBudget` + `BudgetTransaction` ledger (indexed by `metadata->>'model'/'provider'`) + `Ai::AgentExecution.cost_usd` | `ExecutionGateService` denies at `remaining_cents <= 0` |
| Context efficiency | `Ai::TaskComplexityAssessment.input_token_count` (the only per-op context size persisted today) + **P0 fix**: persist injector `token_estimate` + real per-section breakdown into `ai_agent_executions.performance_metrics` | `Ai::Memory::ContextInjectorService` (computes, currently discards) |
| Skill utilization | `ai_skill_usage_records` (outcome, duration, per execution) + `ai_skills.effectiveness_score/usage_count` | written ONLY inside `Ai::McpAgentExecutor` → the driver MUST go through the mission/agent path (§6), never bare MCP tool calls |
| Learning momentum | `Ai::CompoundLearning.injection_count/effectiveness_score` + **`injection_success_rate`** (`GET /api/v1/ai/learning/compound_metrics`, MCP `learning_metrics`) + `SharedKnowledge.usage_count` | capture at execution end, `record_injection!` at recall, boost on success |
| Infrastructure truth | `System::NodeInstance`/`Node`/`NodeModuleAssignment` state vs live PVE (`pvesh`), agent handshake (`runtime/handshake` → `DockerHost` row) | the smoke-seed assertions, reused |

## 4. Phases

### P0 — Pre-flight (measurement integrity + placement)
The run is meaningless until these land. Each is small and independently testable:

1. **Cost attribution bug**: `Ai::AgentExecution` calls `agent.model` (undefined; the
   model defines `resolved_model`) at `agent_execution.rb:210/:247` — any execution
   missing `output_data["model_used"]` records cost 0.0 and debits 0 cents. Fix +
   red-first spec. *Without this, the budget ledger lies.*
2. **`AgentBudget#allocated_cents`** — called in 4 places (incl.
   `context_injector_service.rb:421`) but neither column nor method exists. Fix or
   excise. *Latent NoMethodError on the exact paths the dry-run exercises.*
3. **Context metrics persistence**: `ContextInjectorService` returns `token_estimate`
   + `breakdown` and every call site discards them; breakdown values are presence
   flags, not counts. Persist real per-section token counts into
   `ai_agent_executions.performance_metrics` (no new table).
4. **Routing gate**: `ai_task_tier_routing_enabled` defaults OFF — enable **for the
   dry-run account only** as a setup step (without it, zero `RoutingDecision` rows
   are written and §3's first oracle is empty).
5. **Placement**: the provider pins `default_node: dna` and `default_storage:
   dna-data`. Add per-instance node targeting (dna|rna) + an rna-visible storage
   mapping — itself a fair test of "create infrastructure capability on demand".
6. **Doc drift**: `extensions/system/CLAUDE.md` says "18 seeded scripts, 8 passes";
   the catalog is 28 seeds/9 passes (33 files on disk). Correct while touching.

### P1 — Baseline run (operator in the loop)
Driver (§6) submits the dry-run brief through the real concierge/mission pipeline on
dev-cell. Operator approves `review_plan` and `handoff` live. The run deploys the
composed stack across dna+rna, asserts §5, tears down on pass. Outputs the first
**run report** (§7) — this defines "normal" for enforcement thresholds.

### P2 — Repeatable harness (headless)
Same run, `dryrun-<runId>` marker on the mission; harness approves its own gates
individually (never batch). Target: one command, exit code = finding count, mirroring
`scripts/ai-smoke/run.mjs` conventions (`--md --json` reports). Add to the operator
runbook set.

### P3 — Momentum tracking
Run-over-run deltas: `injection_success_rate` trend, routing `savings_usd` trend,
context tokens/op trend, time-to-deployed trend. A run that repeats a mistake a
prior run's learning should have prevented is a **momentum failure** even if the
infrastructure deploys.

## 5. Pass/fail criteria (v1 — report-first)

Per-operation, graded not enforced (except SAFETY, always enforced):

- **SAFETY (hard)**: kill switch respected; budget ceiling never exceeded (gate
  denial observed if approached); no VM outside the `dryrun-` naming prefix touched;
  no writes to ops-hub; VM protection flags honored; teardown complete on pass
  (verified against live `pvesh`, not DB rows — presence on disk is never proof).
- **Routing (graded)**: every LLM operation has a `RoutingDecision`; no unjustified
  escalation (governance fails these closed — assert it did); `recommended_tier` vs
  `actual_tier_used` mismatches reported with the rationale; per-seam latency never
  pooled across `latency_seam` values.
- **Context (graded)**: per-op `input_token_count` within budget
  (`DEFAULT_TOKEN_BUDGET = 4000` injector-side); report the per-section breakdown;
  flag any op whose context grew without a corresponding relevance source.
- **Skills (graded)**: expected executor skills for the composed stack
  (`provision_full_stack`, `docker_provision`, module assignment executors) show
  `ai_skill_usage_records` rows with positive outcomes; zero-usage expected skills
  reported.
- **Agent economy (graded)**: number of agent executions vs the plan's step count
  (no unexplained fan-out); duty-cycle tagged executions stay within
  `MAX_ACTIONS_PER_CYCLE`.
- **Learning (graded)**: ≥1 `CompoundLearning` captured from the run; on repeat
  runs, injections recorded and credited (`injection_success_rate` non-degrading).
- **Outcome (hard)**: the composed stack reaches its declared state — instances
  running on the declared nodes (dna AND rna), runtime handshake completed
  (`DockerHost` row appears), modules applied — within the run's time budget.

## 6. Driver design constraints (from the 2026-08-08 survey)

- Drive via **REST mission endpoints** (`POST /api/v1/ai/missions/:id/{start,approve,advance}` +
  internal per-phase endpoints); the five `platform_provisioning_*` MCP tools are not
  reliably exposed to external sessions. Execution is reachable ONLY by approving
  `review_plan` — by design (a separate execute action raced and double-provisioned).
- The run must flow through `Ai::McpAgentExecutor` (mission/agent path) or skill
  utilization records nothing — bare MCP tool calls bypass the write path.
- `latency_seam` tags (`agent_execution` / `ralph_iteration` / `router_request`)
  partition latency data; never aggregate across them.
- Two silent-zero traps: `CostCalculationService.calculate` returns 0.0 for
  unrecognized model ids (assert model ids resolve), and pre-P0 cost rows may be
  zeroed by the `agent.model` bug — baseline only counts post-P0 data.
- `local_qemu` under `POWERNODE_LIBVIRT_MODE=real` is the future **recording tier**
  for provider-side determinism; v1 uses Proxmox live.

## 7. Run report

One markdown + one JSON per run (ai-smoke conventions): charter echo, per-dimension
grades with the underlying record IDs (RoutingDecision/AgentExecution/SkillUsage/
CompoundLearning), cost ledger extract, infrastructure timeline (intent → deployed →
torn down), findings ranked by severity, and the momentum deltas vs the previous run.
Exit code = finding count.

## 8. Safety rails (always on)

Kill switch (`bail_if_ai_suspended!` paths) honored end-to-end; `Ai::AgentBudget`
ceilings on every participating agent; `dryrun-` naming prefix is the blast-radius
boundary for every created artifact (VM, template, module assignment, mission);
Proxmox VM protection flags on everything the run must never touch; retained-on-fail
artifacts carry the runId for forensics and a documented manual-cleanup command.

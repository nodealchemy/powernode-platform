# Provisioning decomposition redesign — deterministic synthesis (2026-08-09)

Status: implemented on `dev-loop/dev-improve`, staged only (operator gates deploy).
Subsumes IMP-019fe7f0 (run-f scale explosion); makes the F-1 (IMP-019fe76e) and
docker-dedup (IMP-019fe7e0) guards structurally unnecessary on the recognized path
while keeping them as a safety net for the LLM fallback path.

## The problem

`Ai::Provisioning::PlanComposerService#compose!` turns a captured Project Brief into
an `Ai::GoalPlan`. For a recognized provisioning scenario the brief already fully
determines the plan:

- `brief["scale"]["initial"]` → total instance count
- `brief["regions"]` → placement (count split across them)
- `preferred_template` / `preferred_provider` → resolved deterministically upstream
- `use_case` / `intent` / `runtime_hint` naming container work → one wired
  `docker_provision` step per instance

Yet the composer called the LLM decomposer (`Ai::Autonomy::GoalDecompositionService`)
to emit a variable step DAG, then ran six correction passes (`rewrite_steps!`) to beat
it into shape: advisory-step pruning + renumbering, skill mapping + input resolution,
same-target collapse, region fan-out, runtime-leg completeness, docker wiring + dedup.

## Root cause

The variance is entirely the LLM's. The platform-autonomy-dryrun campaign ran the
**same brief** (scale.initial=3, regions dna+rna, container-runtime use case) four
times and got a differently broken plan each time:

| Run | LLM decomposition defect | Patch it forced |
|-----|--------------------------|-----------------|
| c | 3 docker steps (correct by luck) | — |
| d | 0 docker steps | `ensure_runtime_leg!` (IMP-019fe76e) |
| e | 2 docker steps → 6 after fan-out | `collapse_redundant_docker_steps!` (IMP-019fe7e0) |
| f | count 9+9 = **18 instances for a 3-instance brief**, est. $1008/mo | queued IMP-019fe7f0, unpatched |

Each guard fixes one dimension of variance; the next run reveals another. The brief
extraction was correct in every run. Guarding an unnecessary source of randomness is
the wrong altitude — the fix is to remove the randomness.

## The redesign

**For a recognized provisioning scenario, synthesize the plan directly from the brief.
No LLM call, no correction passes.**

- The recognized-scenario predicate is `ComposerRouter#deterministic_provisioning?` —
  the exact predicate that routes briefs to `PlanComposerService` in the first place.
  It is hoisted to a class method (`ComposerRouter.deterministic_provisioning?`, the
  instance method delegates) so the composer consults the same single source of truth.
  All three production entry points (internal phase controller, concierge
  ProvisioningTool, deep-link REST endpoint) route through `ComposerRouter#select`, so
  in production every brief reaching `compose!` takes the synthesis path.

### Synthesis (`synthesize_plan!`)

From the brief, in order:

1. `total = scale.initial` (floor 1).
2. `regions = resolve_regions_for_brief(brief)` — every named region, resolved
   strictly (no silent substitution), de-duplicated, brief order.
3. `shares = split_count_across(total, regions.size)` — remainder to the earliest
   region, never a zero share. No regions resolved (core mode / region-less brief) →
   a single share carrying the full count, region left to the existing fallback.
4. One `provision_full_stack` step per share, numbered 1..R, no dependencies
   (regions provision in parallel). Inputs via the existing
   `merge_resolved_inputs!` — count + `provider_region_id` preset per share, then
   template (`preferred_template` else default), instance type, `dry_run`,
   `mission_id`, `name_prefix` provenance (F3), and the `brief` itself, exactly as
   the rewrite path stamped them.
5. When `brief_demands_runtime?` (unchanged predicate: `runtime_hint: docker` or
   docker/container language in use_case/intent): for each provision step with count
   k, k `docker_provision` steps, each depending **only** on its own provision step
   and wired via the runner's cross-step mechanism
   (`depends_on_outputs.node_instance_id = { from_step, path:
   "outputs.node_instance_ids", select: <index> }`). Total docker steps == total
   instances, by construction.

The plan record mirrors the decomposer's shape (versioned per goal, `status: draft`)
with `plan_data.composer = "deterministic_synthesis"` for provenance.

Everything after plan-shape composition is unchanged and common to both paths:
compose-time prerequisite check (IMP-019fe647), role-module attachment,
`deploy_app_code` append for repo briefs, plan pointer persistence, budget surfacing
in the snapshot (F7 — the brief rides in step inputs as before, so
`PlanSnapshotService` budget comparison works unmodified).

### Defects now structurally impossible on this path

- **run f** (scale explosion): step counts are `split_count_across(scale.initial, …)`
  — they sum to `scale.initial` by construction. Never 18 for a 3-brief.
- **run e** (duplicate docker): docker steps are generated once, one per instance —
  there is no independent step-set to dedup.
- **run d** (missing runtime leg): the leg is emitted whenever the brief demands it —
  there is no omission to repair.

### What happens to the six correction passes

**Kept, as the safety net for step-sets that still arrive from elsewhere:**

- The LLM decompose + `rewrite_steps!` pipeline remains intact and is used when
  `compose!` is invoked with a brief the predicate does not recognize (only possible
  for direct instantiation — the router never sends such a brief here).
- `compact_existing_plan!` (collapse passes) still serves cached pre-redesign plans
  on the deep-link read path.
- The docker wiring/dedup and runtime-leg passes keep their unit-level specs green;
  nothing was deleted.

The synthesized path simply never invokes them — bypassed, not removed.

### The novel-intent path is untouched

`Ai::Missions::MissionComposer` (the general LLM composer for novel intents) is not
modified. `ComposerRouter#select`'s routing logic is unchanged — only the predicate's
implementation moved from instance to class scope, with the instance method
delegating (router specs exercise the instance method and stay green). Briefs that
are not provisioning-shaped continue to route to `MissionComposer` exactly as before.

### Deliberate behavior retentions (flagged for the operator)

- **CostCapGuard still gates the synthesis path.** The guard exists to cap LLM spend
  and synthesis spends none, so it could arguably be skipped when the brief is
  recognized. Kept as-is to avoid a caller-visible contract change (compose! → nil +
  `cap_exceeded_payload`) outside this task's scope. Possible follow-up: bypass the
  guard when no LLM call will be made.
- Provider clarification (M2 BYOC), goal reuse/GC, and the `AgentMissingError` agent
  requirement are unchanged — the goal still needs an owning agent even though no
  LLM is called on this path.

## Test plan

New spec `spec/services/ai/provisioning/plan_composer_deterministic_synthesis_spec.rb`
(written red-first against the old pipeline):

- **No-LLM invariant**: `GoalDecompositionService#decompose` is never called for a
  recognized brief.
- **Run-f pin**: scale.initial=3 + regions dna,rna → provision counts sum to exactly
  3, split 2+1 — repeated compositions always produce the same shape.
- **Run-e / run-d pin**: the same brief (container-runtime use case) → exactly 3
  docker steps, one per instance, each wired (`from_step`+`select` covering
  [dna,0],[dna,1],[rna,0]) and depending only on its own provision step.
- **F3 provenance**: `name_prefix` (from `dryrun_run_id`) and `mission_id` stamped on
  provision inputs.
- **F7 budget**: snapshot of a synthesized plan surfaces the cap-vs-estimate block.
- Single-instance and no-runtime briefs: one provision step, zero docker steps.
- Region-less brief and core mode (System::* absent): single full-count step,
  fallback/nil resolution — existing core-mode specs stay green.
- Unrecognized brief via direct instantiation: still takes the decompose+rewrite
  path (fallback preserved).

Existing suites: `spec/services/ai/provisioning/` in full, plus
`spec/services/ai/missions/composer_router_spec.rb` and `mission_composer_spec.rb`.
Legacy pipeline specs that drove `compose!` with a decompose stub were repointed at
unrecognized briefs (they test the fallback pipeline, which is exactly where that
pipeline now lives); collapse-clamp coverage moved to the pass level so the safety
net keeps its own tests.

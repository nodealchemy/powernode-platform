# Platform Vision Gap Discovery — 2026-08-06

**Type**: discovery/audit (report only; nothing implemented) · **Requested scope**: platform
insufficiencies vs the vision, with particular attention to system functionality, MCP, AI
skills, autonomy, and self-improvement.
**Baselines**: core @ `d222c0eeb`, extensions/system @ `4dc4045c`.
**Method**: five narrowly-scoped parallel read-only audits (AI skills + learning loops; core
autonomy loop; self-improvement pipeline; MCP runtime; system-extension residual
verification), each against the operator's stated north stars
([[north-star-autonomous-fleet-orchestration]], [[north-star-component-per-instance-topology]],
guardrail F3-03: every autonomy proceed-lane ends in an actuator or an operator). Every
load-bearing claim quoted below was independently re-verified against source by the lead
session before inclusion (see §8). Companions: `system-extension-discovery-review-2026-08-03.md`
(modules/templates — mostly drained), `system-frontend-dashboard-gap-analysis-2026-08-06.md`
(UI side, same day).

---

## 1. Executive summary — the last-mile dead-wire pattern

The dominant, repeated defect class across every audited subsystem is: **sensing, gating,
and bookkeeping are built and running; the write-back or actuation arm at the end of the
lane is missing, orphaned, or broken — and the failure is silent.** Nine independent
instances were found and verified:

| # | Lane | Built and working | Dead at the last mile |
|---|------|-------------------|------------------------|
| 1 | Core OODA loop | Sensors cron every 15 min, observations written | `RalphLoopClosureService`/`DutyCycleService#execute_cycle` have **zero callers** — observations are read once as prompt prose, then deleted |
| 2 | Module promotion | `ModulePromotionSensor` fires, DecisionEngine routes, operator approves | No `REMEDIATION_APPLIERS` entry; `ModulePromotionService.promote!` called **nowhere** — approval is a no-op |
| 3 | Provisioning adaptation | `provisioning_adapt` composes + approval arc (bf938a4e5) | Diff plan never stamped on the mission pointer; `resolve_plan!` can never find it; `auto_apply` flag computed, never read |
| 4 | Adaptation approval | ApprovalRequest created and resolvable | Cascade targets `Ai::Agent`, which has no `on_approval_decision` — silent no-op via `respond_to?` guard |
| 5 | Learning effectiveness | Injection counted on every `dev_next_task` | Credit path unreachable from the dev-loop; hard `0.0` written at 3rd injection — **corpus degrades in proportion to use** |
| 6 | Skill auto-evolution | Weekly cron, worker logs success | `SkillMutationService` queries columns that don't exist (`success::int`, `version_number`, `variant_a_id`); has never executed one query successfully; zero specs |
| 7 | Prompt refinement | `SelfLearningService` files recommendations; operator approves | `apply_recommendation!` has no `prompt_refinement` branch — status flips to `applied`, skill prompt untouched (a **false** actuator: audit trail claims it landed) |
| 8 | Skill A/B testing | Versions, traffic split, end_ab_test comparison all exist | Nothing autonomous ever writes `SkillVersion` counters; nothing schedules start/end — incumbent always wins |
| 9 | Goal advancement | Goals, decomposition, trust-tiered scheduler all exist | Scheduler called only from the orphaned closure service; the only scheduled goal job can **abandon** goals, never advance them |

Two structural conclusions:

1. **The platform cannot currently improve itself without an external session driving.**
   Discovery of code-quality findings has no scheduled driver (the analyzers are MCP tools
   nothing invokes), and drain verification accepts self-attested `passed` without ever
   reaching `TestVerificationService` — so even a fully autonomous drain would record
   unverified claims.
2. **The failure mode is uniformly silent.** Rescue-and-log inside per-item loops, workers
   that log success without reading response bodies, `respond_to?` guards over missing
   hooks, feature-flag gates that return `{skipped: true}` into a void, and a validation
   enum mismatch that rejects a sensor's every row — every dead arm *looks* alive from the
   outside. The 08-06 frontend gap analysis compounds this: there is no UI that would
   reveal any of it.

Highest-leverage sequencing (small fixes, outsized unlock):
**(a)** credit injected learnings in `dev_complete_task` (defuses active corpus poisoning);
**(b)** wire `REMEDIATION_APPLIERS["system.module_promotion_ready"]` → `ModulePromotionService.promote!` (one file; completes an already-approved autonomy lane);
**(c)** schedule `RalphLoopClosureService#execute_cycle` (activates the complete, already-written OODA cycle);
**(d)** fix the two sensor-wiring one-liners (enum mismatch + missing `.compact`) that silently suppress the observation stream everything else depends on;
**(e)** route `dev_complete_task` results through `TestVerificationService` before accepting `passed`.

---

## 2. Self-improvement pipeline (audit A)

Verdict: **the middle of the pipeline is solid** (promotion, dedupe, dismiss-cascade,
campaign aggregation every 30 min via `AiCampaignDiscoveryJob`, scoreboard); both ends are
open. Findings (all evidence verified on HEAD):

1. **No autonomous code-quality discovery driver** | P0. `discover_improvements` returns
   guidance text (`improvement_tool.rb:143-193`); `StaticAnalysisService`'s only invoker is
   the MCP `code_analysis_tool.rb:126`; none of worker's ~60 cron entries reference any
   analyzer. Autonomous recommendation creation exists but only for agent/skill-shaped
   types; `RecommendationSensor` deliberately filters code-quality types out
   (`recommendation_sensor.rb:67`). Every code finding in the DB got there because an
   external brain ran a scan.
   Fix seam: cron → server-side scan service → `create_improvement`'s idempotent persistence.
   `capability_gap|server/app/services/ai/tools/improvement_tool.rb|no-scheduled-code-discovery-driver`
2. **Learning outcome-crediting unreachable from the dev-loop — actively poisons the
   corpus** | P0. Injection: `compound_learning_service.rb:219-237` ← `dev_loop_tool.rb:725`
   (every claim). Credit: only `post_execution_extract` (agent/team execution paths) and the
   manual `reinforce_learning`. `record_injection!` itself calls `recalculate_effectiveness!`
   (`compound_learning.rb:155-158`), which at `injection_count >= 3` writes
   `positive/injection` — a hard `0.0`, not NULL (`:326-331`). Consequences: cross-team
   promotion permanently barred (`effectiveness_score IS NULL OR >= 0.4` gate,
   `compound_learning_service.rb:260`; `compound_learning_promotion` auto-enabled);
   recall ranking **inverted** at 5 injections (`effective_importance`,
   `compound_learning.rb:111-116` — importance 0.8 → 0.395); and the dormant
   `compound_learning_scheduled_verification` flag would mass-`disprove!` the injected
   corpus if ever enabled (`verify_unverified_batch`, `:394-425`).
   Fix seam: persist injected learning IDs on the `RalphIteration`; resolve in
   `complete_task`'s passed branch.
   `code_lint|server/app/services/ai/tools/dev_loop_tool.rb|dev-complete-task-never-credits-injected-learnings`
3. **`query_learnings` is strict-AND LIKE; the semantic path exists and is unused** | P1.
   `learning_tool.rb:79-89` chains AND'd LIKEs (multi-word intent queries return zero —
   reproduced live). Learnings DO have a 1536-dim embedding + HNSW index
   (`schema.rb:1437,1469`) and `ranked_learning_candidates` already does embedding-first
   retrieval with OR keyword fallback (`compound_learning_service.rb:878-907`). The MCP
   recall surface is the one consumer using neither. Wiring, not infrastructure.
   `code_lint|server/app/services/ai/tools/learning_tool.rb|query-learnings-strict-and-no-semantic-fallback`
4. **`dev_complete_task` accepts self-attested "passed"** | P0. `check_results` free-form,
   stored verbatim; passed branch hardcodes `checks_passed: true` (`dev_loop_tool.rb:453`,
   verified); `apply_linked_recommendation!` then flips the offer to `applied`.
   `TestVerificationService` (the real gate, canary-protected) is reached only by the
   platform-agent path (`internal/ai/ralph_loops_controller.rb:130`). The validate.sh
   guardrail is prompt text, not enforcement.
   Fix seam: evaluate `check_results` via `TestVerificationService` in `complete_task`;
   remap to `blocked` on failure (pattern already exists for the G10 scope guardrail).
   `test_gap|server/app/services/ai/tools/dev_loop_tool.rb|complete-task-bypasses-test-verification-gate`
5. **Outcome→learning closure is executor-discretionary** | P1. `capture_learning`/
   `embed_learning_mid_run` work but both `return if learning.blank?`; nothing synthesizes
   a fallback from summary/check_results/files_changed; `apply_linked_recommendation!`
   writes no learning at all.
   `capability_gap|server/app/services/ai/tools/dev_loop_tool.rb|learning-capture-optional-no-fallback`
6. **`revert_improvement` is bookkeeping; the revert-rate throttle is computed and never
   read** | P2. `RalphTask#revert!` sets two columns; `improvement_scoreboard`'s
   `throttled:` flag (`ralph_task.rb:210`) has zero consumers — a bug class reverting 50%
   of the time neither throttles discovery nor gates approval.
   `dead_code|server/app/models/ai/ralph_task.rb|revert-throttle-computed-never-consumed`
7. **Knowledge lifecycle: mechanized except retirement** | P2. Dedupe/quality/embedding
   backfill/import all run daily; but `archive` has one caller (manual MCP delete), nothing
   auto-retires stale entries, and nothing validates that `guidance-*` entries still match
   live code — the cross-executor rule carrier can drift silently.
   `capability_gap|server/app/services/ai/memory/shared_knowledge_service.rb|no-automated-knowledge-retirement`
8. **Campaign proposals require manual approval** | P2 (deliberate design, recorded for
   completeness — the human gate at approval is the intended shape).

## 3. Core autonomy loop (audit B)

Stage status: **1 PARTIAL · 2 PARTIAL · 6 MISSING · 7 MISSING (in core)**. The provisioning
forward path (brief → compose → approve → execute → verify → handoff) genuinely reaches
actuators; team *execution* genuinely reaches actuators. Everything cyclical is dead:

1. **The entire core OODA decide/act loop has no caller** | P0. `DutyCycleService#execute_cycle`
   and `RalphLoopClosureService` (a complete observe/orient/decide/act/learn cycle with real
   dispatch, `ralph_loop_closure_service.rb:34-52`) are reachable only from their own specs
   (monorepo grep verified). The observe half IS scheduled (15-min cron →
   `AiObservationPipelineJob`); its output is rendered into prompt prose and deleted.
   `autonomy-loop|server/app/services/ai/autonomy/ralph_loop_closure_service.rb|ooda-closure-service-has-no-scheduled-driver`
2. **`provisioning_adapt` composes a plan no actuator can reach** | P0, F3-03.
   `persist_diff_plan!` creates the plan under a new "Adapt:" goal and never stamps
   `mission.configuration["plan"]["plan_id"]`; the only execution entry resolves exclusively
   from that pointer with a literal-nil fallback (`provisioning_controller.rb:214-220`);
   re-running execute hits the completed original plan → idempotency no-op. `auto_apply`
   computed/surfaced/stored, never read. The service's own header comment describes append
   logic the runner does not contain.
   `autonomy-actuator|server/app/services/ai/provisioning/adaptation_proposer_service.rb|adaptation-diff-plan-never-reaches-runner`
3. **Adaptation approval cascades to `Ai::Agent`, which has no hook** | P0.
   `ApprovalWorkflowService` hardcodes `source_type: "Ai::Agent"`; `notify_source_of_decision`'s
   `respond_to?(:on_approval_decision)` guard makes resolution a silent no-op (implementors
   verified: DeferredOperation, Mission, CampaignLand, AgentProposal,
   ImprovementRecommendation — not Agent). `AdaptationProposerService:523` is the last
   caller of this legacy service; everything else migrated to `Ai::Approvals::Gateway`.
   Core mode fails separately: without the governance capability, `request_approval` returns
   nil and no `:proceed` branch exists.
   `approval-chain|server/app/services/ai/autonomy/approval_workflow_service.rb|autonomy-approvals-bind-to-agent-with-no-cascade-hook`
4. **Goals are inert** | P0. Only scheduled goal job is daily maintenance that can only
   `abandon!`; `GoalDrivenSchedulerService#next_action` (decompose/validate/auto-approve/
   execute-step) is called only from the orphaned closure service. Goals move only on manual
   MCP calls.
   `autonomy-loop|server/app/services/ai/autonomy/goal_driven_scheduler_service.rb|goals-have-no-scheduled-advancement-driver`
5. **`CodeChangeSensor` fails enum validation on every write** | P1. Returns `"code_changes"`;
   `SENSOR_TYPES` has `code_change` (verified). RecordInvalid rescued+logged → permanently
   silent. Only mismatch among the ten sensors.
   `sensor-wiring|server/app/services/ai/autonomy/sensors/code_change_sensor.rb|sensor-type-code-changes-fails-enum-validation`
6. **Three sensors return nil-bearing arrays; one nil aborts the agent's whole collection**
   | P1. `goal_progress`, `governance`, `stigmergic_signal` lack `.compact` (verified: zero
   occurrences); `create!(nil)` raises ArgumentError which the inner RecordInvalid rescue
   does not catch; dedup window == cron period, so routine. Silences the three most
   autonomy-relevant sensors.
   `sensor-wiring|server/app/services/ai/autonomy/sensors/goal_progress_sensor.rb|missing-compact-nil-aborts-observation-pipeline`
7. **`requires_action` has no actionable route** | P1 — the core analogue of the extension's
   `capability_gap` bug: the `actionable` scope has zero call-sites; the flag's only live
   reader appends "⚡ requires action" to a prompt string.
   `sensor-wiring|server/app/models/ai/agent_observation.rb|requires-action-flag-has-no-actionable-route`
8. **`DutyCycleService` act handlers are logging stubs** | P1 (compounds #1; observations
   marked processed and burned).
   `autonomy-loop|server/app/services/ai/autonomy/duty_cycle_service.rb|act-phase-handlers-are-logging-stubs`
9. **Post-handoff mission loop is ticked only by the system extension** | P1 (core-mode gap:
   `driven_by: "FleetAutonomyService"`, `scheduling_mode: "manual"` — core schedulers select
   only autonomous/continuous; with the extension disabled every mission parks in `adapting`).
   `core-mode-gap|server/app/controllers/api/v1/internal/ai/provisioning_controller.rb|handoff-loop-only-ticked-by-extension`
10. **Team assembly is on-demand only** | P1. Execution half reaches real actuators
    (worker job → strategy classes). Assembly half: `SelfOrganizingTeamService` reachable
    only via two on-demand MCP actions; `AiTeamOptimizeJob` unscheduled; no path decomposes
    an objective into an assembled team.
    `team-assembly|server/app/services/ai/coordination/self_organizing_team_service.rb|team-self-organization-has-no-autonomous-driver`
11. **No core capacity sensor or actuator** | P1. `target_size` has zero references in
    server/app; stage 6's closed loop does not exist in core in any form.
    `capacity|server/app/services/ai/autonomy/sensors|no-core-capacity-sensor-or-actuator`
12. **Autonomy constraints hardcoded** | P2. `TRUST_THRESHOLDS` USD ceilings ($1/$5/∞) and
    `MAX_DAILY_ACTIONS = 50` in source; zero SiteSetting/Account#settings references under
    ai/autonomy + ai/provisioning — against the standing no-hardcoded-budgets rule.
    `config-drift|server/app/services/ai/autonomy/goal_driven_scheduler_service.rb|trust-usd-thresholds-hardcoded-not-db-driven`

## 4. AI skills + learning loops (audit C)

Verdict (verified): discovery/contextualization/execution work for the 54 executor-backed
system-extension skills — the set fleet autonomy actually uses. Measurement flows but is
unattributable; **all three write-back arms are broken**; two crons report weekly success
over no-ops.

1. **`SkillMutationService` schema drift — weekly auto-evolution cron has never worked** |
   P0. Every query references nonexistent columns (verified against schema.rb:
   `success::int` vs actual `outcome` string; `version_number`/`status`/`variant_a_id`
   absent from `ai_skill_versions`/`ai_ab_tests` shapes). Reachable from the weekly cron,
   `WorkerJobService`, and the MCP `SelfImprovementTool`. Zero specs. Per-account rescue
   inside the loop → controller returns `mutated: 0` → worker logs success.
   `bug|server/app/services/ai/self_improvement/skill_mutation_service.rb|skill-mutation-service-schema-drift`
2. **Approving a `prompt_refinement` recommendation is a status flip** | P0, F3-03 (false
   actuator). `apply_recommendation!` branches verified: provider_switch,
   timeout_adjustment, cost_optimization, skill_health, skill_creation — no
   prompt_refinement → generic `apply!` (status only). Operator-visible "applied" with no
   skill change.
   `bug|server/app/services/ai/learning/improvement_recommender.rb|prompt-refinement-apply-is-noop`
3. **21 core global skills never get a KG node → invisible to `discover_skills`/router** |
   P0. `sync_to_knowledge_graph` returns unless `account_id.present?` (skill.rb:398,
   verified); both discovery entry points query per-account nodes; the only global-covering
   writer (`BridgeService#sync_all_skills`) is manual or behind the default-OFF
   `skill_optimization` flag. Invisible set includes `design-skill-from-intent` and
   `design-agent-team-from-intent` — the skill-authoring entry points themselves.
   `bug|server/app/models/ai/skill.rb|global-skills-never-kg-synced`
4. **`skill_optimization` default-OFF silences three maintenance crons** | P1. Flipper
   auto-enables only `skill_self_learning` + two compound-learning flags (verified,
   flipper.rb:95-100); daily/weekly/monthly OptimizationService crons return
   `{skipped: true}`; the worker job never reads the response body and logs success.
   Skipped work includes prompt refinements, capability-gap detection, effectiveness
   recalc, and the monthly re-embed that is the only automatic remedy for #3.
   `bug|server/config/initializers/flipper.rb|skill-optimization-flag-default-off-silent-cron`
5. **A/B variants can never win** | P1. `SkillVersion#record_outcome!`'s only non-spec
   caller chain is operator-driven HTTP; the autonomous path updates only `Ai::Skill`
   counters; nothing schedules start/end_ab_test. Comparison runs on seeded defaults —
   incumbent always wins.
   `bug|server/app/services/ai/skill_graph/self_learning_service.rb|skill-version-counters-never-written-autonomously`
6. **Skill effectiveness is not attributable** | P1. Same outcome written against ALL
   attached active skills → `effectiveness_score` measures the agent, not the skill; yet
   `auto_mutate_underperforming!`, decay, and health scoring all consume it.
   `design|server/app/services/ai/skill_graph/self_learning_service.rb|skill-effectiveness-not-attributable`
7. **Seven skill slugs in the platform binding seed don't exist; bindings silently
   dropped** | P1. `next unless skill` swallows: incident-analysis, performance-tuning,
   devops-automation, content-localization, user-research, compliance-review,
   security-audit. The SRE agent gets 1 of 5 assigned skills. Extension already solved this
   (`SkillBindings.validate!` collects-and-raises) — mirror it.
   `bug|server/db/seeds/platform_skill_assignments_seed.rb|platform-skill-assignments-silently-skip-missing-slugs`
8. **`SkillBindings.validate!` runs only at seed time** | P2.
   `gap|extensions/system/server/app/services/system/ai/skills/skill_bindings.rb|skill-bindings-validate-seed-time-only`
9. **MCP `create_skill` cannot produce an executable skill** | P2. Tool allowlist omits
   `metadata`/`recipe`; execution dispatch requires `metadata["executor_class"]` or
   `metadata["recipe"]`. Agent-created skills are working prompt fragments, never routed
   executors — possibly a deliberate safety boundary, but undocumented, and it means
   `design-skill-from-intent`'s own recipe output cannot be saved via the agent-facing tool.
   `gap|server/app/services/ai/tools/skill_tool.rb|mcp-create-skill-cannot-set-executor-or-recipe`
10. **`SkillRecipeRunner.execute`/`dry_run` have no production caller** | P2. The resume
    half is wired end-to-end to rows nothing creates.
    `gap|server/app/services/ai/skill_recipe_runner.rb|recipe-runner-execute-has-no-production-caller`
11. **Specialty coverage**: most domains covered (106 seeded skills across five seed
    files); genuine gaps: **backup/DR — zero skills** (despite scheduled backup jobs),
    cost/capacity — one, storage — one.
    `gap|server/db/seeds/ai_skills_seed.rb|no-backup-dr-or-cost-specialty-skill`

## 5. System extension residuals (audit D — verification of the 08-03 review on HEAD)

| Item | Status |
|---|---|
| Purpose search over modules/templates (embeddings, discover actions, backfill+coverage) | **CLOSED** |
| compose_preview over MCP + conflict detection on every write path | **CLOSED** |
| BASE_GUARDRAILS fleet-discovery guidance | **CLOSED** |
| fulfill_capability_request reachability (3 skill seeds, approve endpoint, author_module gaps ride the plan) | **CLOSED** |
| Build throughput (retired the single-runner CI queue; `NativeModuleBuildOrchestrator` parallel dispatch with SiteSetting cap + per-module `CiRunnerLease`) | **CLOSED** |
| Manifest `verify:` probe block | **PARTIAL** — a different mechanism shipped: server-computed `ModuleSmokeProbe` → Go agent `ProbeModuleSmokeHandler` (3 fixed checks). No manifest-authored probes, no `resolves_to`, no standing sensor on probe failures |
| Post-compose capability verification | **PARTIAL** — module-scoped smoke verify exists and gates the fulfillment sweep; no capability-scoped "assert node N provides C" call; not a standalone MCP action |
| **Module promotion ladder automation** | **OPEN — dead-wired** (see §1 table row 2; verified: `ModulePromotionService` has 1 definition, 4 comment refs, 0 call-sites; no applier entry). built→staging has zero automation |
| Capability taxonomy | **OPEN** — syntax regex only; no registry/enum (contrast `NodeModuleCategory::PLATFORM_TAXONOMY`) |
| Template versioning/closure audit (approved offer `019fce79-4513`) | **OPEN** — `LifecycleAuditable` included only in `NodeInstance`; no history model/migration exists. Offer is approved-but-not-yet-drained; flagging so it isn't lost |

New system-extension findings to file:
- `bug|extensions/system/server/app/services/system/fleet/decision_engine.rb|module-promotion-ready-has-no-remediation-applier`
- `capability_gap|extensions/system/server/app/services/system/module_smoke_probe.rb|no-capability-scoped-verification-primitive`
- `capability_gap|extensions/system/modules/.schema/module-manifest.schema.json|no-manifest-authored-verify-probes`
- `capability_gap|extensions/system/server/app/services/system/capability_resolver.rb|capability-tags-free-form-no-registry`

## 6. MCP runtime (audit E)

Verdict: **the MCP *server* side is much stronger than expected** — resources, prompts,
completions and the 2026-07-28 stateless era are genuinely implemented (not stubbed), the
protocol version set is current (not stale), and core tool-catalog integrity is clean (all
56 core classes diffed: zero dispatched-but-unregistered, zero registered-but-undispatched).
The two vision pillars actually **absent** are MCP-client and cross-plane/federation, plus
one live authorization hole. Findings (verified on HEAD):

1. **Instance principals bypass default-deny via `resources/*`, `prompts/*`,
   `completion/complete`** | P0 (grants breach). The only principal gate is inside
   `handle_tools_call` (`streamable_http_controller.rb:563`, `may_invoke?`). Verified:
   `handle_resources_read` (`:686-694`) constructs `NativeResourceProvider.new(account:)`
   with **no principal, no user, no gate**; `native_resource_provider.rb:226` serializes
   `agent.system_prompt` at `powernode://ai/agents/{id}`, and `complete_uri_template`
   enumerates valid agent IDs for a caller who knows none. `tools/list` is filtered;
   `resources/list` is not. An mTLS node granted literally nothing reads the full prompt
   corpus of the account — defeating the fleet-substrate multi-tenant story
   (`principal.rb:42-88` explicitly reasons that the grant glob is *the only* control, which
   is true for tools and silently false for resources).
   Fix seam: a `dispatch_method`-level principal gate (not per-handler — the lesson from the
   tools/call second-door fix is that opt-in fences get missed at the next door).
   `security|server/app/controllers/api/v1/mcp/streamable_http_controller.rb|instance-principal-unscoped-resources-prompts`
2. **`ai.introspection.view` declared nine times, enforced nowhere, defined nowhere** | P1.
   `Ai::Introspection::McpToolRegistrar.execute_tool` (`:158-198`) is a bare `case` with no
   permission check, reached with no user/principal (`streamable_http_controller.rb:588`).
   Verified: the string appears 9× in the registrar, 0× in `config/permissions.rb`. Because
   `PermissionValidator` resolves through `user.permission_names` (which expands
   `system.admin` to `all_permissions.keys` rather than short-circuiting), the same string is
   simultaneously **unenforced** on the MCP path and **unsatisfiable by anyone incl. admin**
   on the REST path that `sync_to_database!` writes it into. `platform.cost_analysis` and
   `platform.infrastructure` (account-wide financial/health data) are served to any holder of
   a valid MCP token. Both halves need fixing (add the permission AND gate `execute_tool`).
   `security|server/app/services/ai/introspection/mcp_tool_registrar.rb|introspection-tools-permission-unenforced`
3. **Platform-resident agents cannot consume external MCP servers** | P0 (pillar absent).
   `AgentToolBridgeService#build_tool_definitions` (`:439-455`) sources only the local Ruby
   `PlatformApiToolRegistry`; no `McpServer` reference. A working client stack exists
   (`Mcp::SyncExecutionService`, `Mcp::StreamableHttpService`, worker `McpTransportClient`)
   but its only production consumer is the Ralph loop (`ai/ralph/agentic_loop.rb:93-105`),
   which additionally calls remote tools with `user: nil` (no PermissionValidator).
   Fix seam: merge `McpServer`-derived namespaced definitions into
   `AgentToolBridgeService`; branch dispatch on the prefix to `SyncExecutionService`.
   `gap|server/app/services/ai/agent_tool_bridge_service.rb|agent-runtime-no-external-mcp-client`
4. **Cross-plane MCP does not exist; the peer capability token has no Rails verifier** | P0
   (pillar absent — the dev-plane-can't-reach-ops-hub gap). Mint exists in Ruby
   (`peer_capability_token_signer.rb:45-82`); the verifier is in **Go**
   (`agent/internal/a2a/verifier.go`), and Ruby `verify!` has zero production callers.
   `authorize_peer_call` is a pure policy oracle (no HTTP/execution);
   `peer_capability_service.rb:57` requires same-account. Core `FederationPartner` only does
   `.well-known` GETs, never invokes a tool; its inbound `valid_token?` is spec-only; the
   A2A controller authenticates only local JWT/ApiKey. No plane-addressing parameter exists
   anywhere. The two stubs point at each other: a partner with an endpoint+token it never
   checks, and a token no Rails inbound path accepts.
   Fix seam: add a peer-capability-token arm to `McpTokenAuthentication`, calling the
   already-written `PeerCapabilityTokenSigner.verify!`; outbound reuses `StreamableHttpService`.
   `gap|server/app/controllers/concerns/mcp_token_authentication.rb|no-inbound-peer-capability-token-arm`
5. **The MCP protocol path produces no per-call record of any kind** | P1. The complete
   artifact for a `platform.*` call is one untimed pre-execution log line
   (`mcp_platform_tool_registrar.rb:131-135`); `BaseTool#execute` has zero instrumentation;
   `AuditLog|ActivityLog` grep across the MCP paths = 0 hits. `TelemetryService` isn't on
   this path (controller branches to the registrar before `build_protocol_service`), and its
   only sink is a log line with an empty `send_to_external_monitoring`. The REST door does
   all three correctly (validator + `McpToolExecution` row + audit event). No endpoint can
   answer "which tools did agent X call today". Fix seam: one
   `ActiveSupport::Notifications.instrument` around `BaseTool#execute` covers all three
   dispatch doors.
   `gap|server/app/services/ai/tools/base_tool.rb|mcp-tool-call-no-per-call-telemetry`
6. **Rack::Attack is MCP-blind; the 127.0.0.1 self-block is still live in prod** | P1. Zero
   `mcp` hits in `rack_attack.rb`; account-tier throttles resolve accounts only via HS256 JWT
   or `X-API-Key`, neither of which an opaque Doorkeeper bearer or mTLS cert satisfies → every
   MCP request falls to the generic 300-req/15-min per-IP bucket, shared across callers behind
   one IP. The internal safelist is `Rails.env.development?`-only; `/api/v1/mcp/` is absent
   from the `powernode_node_api` safelist. This is exactly the platform-blocks-its-own-worker
   incident, unfixed for MCP specifically.
   `bug|server/config/initializers/rack_attack.rb|mcp-paths-no-internal-safelist-no-account-discriminator`
7. **The per-agent rate limiter never fires on the MCP path** | P2. Registrar guards on
   `if agent_id` (`mcp_platform_tool_registrar.rb:122-129`); the controller passes
   `mcp_agent:` but never `agent_id:`, so `RateLimiter.check!` is always skipped. Combined
   with #6, `tools/call` has no per-principal rate limit at all. One-line fix.
   `bug|server/app/controllers/api/v1/mcp/streamable_http_controller.rb|mcp-tools-call-omits-agent-id-ratelimit`
8. **`track_tool_permission_denied` does not exist** | P2 (latent NoMethodError). Called at
   `protocol_service.rb:214` (verified), defined nowhere → a permission denial on the
   `invoke_tool` path raises NoMethodError mapped to `-32603 Internal error` instead of
   `-32001`.
   `bug|server/app/services/mcp/protocol_service.rb|telemetry-track-tool-permission-denied-undefined`
9. **No progress reporting, no working cancellation** | P1 for a fleet control plane.
   `progressToken|notifications/progress` = zero hits both directions;
   `notifications/cancelled` accepted and discarded (`streamable_http_controller.rb:329-336`,
   both arms identical, no requestId tracked). The tools here are minutes-long side-effecting
   ops (`system_provision_instance`, `system_deploy_platform`); a client cannot show progress
   or abort. Fix seam is additive on the existing SSE writer.
   `gap|server/app/controllers/api/v1/mcp/streamable_http_controller.rb|no-progress-no-cancellation`
10. **Tool-catalog generation omits the nine introspection tools** | P2. The rake task
    sources only `PlatformApiToolRegistry::TOOLS`, but `tools/list` also serves
    `INTROSPECTION_TOOLS` — so the freshly-generated `mcp-tools.md` has no entry for
    `platform.health`/`metrics`/`cost_analysis` (the same nine as #2).
    `bug|server/lib/tasks/mcp_tool_catalog.rake|catalog-omits-introspection-tools`

Lower-severity completeness (P2, filed for the record — see the audit for detail):
stateless-era `subscriptions/listen` unimplemented; outbound client advertises
`sampling`/`roots` it cannot serve + no server-side sampling; `ElicitationService` orphaned;
instance-principal resolver accepts stopped/errored instances
(`security|extensions/system/.../engine.rb|mcp-instance-resolver-accepts-stopped-errored`).

Scorecard: **server protocol features PARTIAL (strong)** · **server auth & scoping PARTIAL**
(tools well-built; resources/prompts bypass, introspection unenforced) · **MCP client
MISSING** for platform agents · **federation/multi-plane MISSING** · **observability MISSING**.
If only three: #1 (live hole, small patch), #3 (the client pillar, one seam), #5 (one
instrument wrapper unblocking the operator question).

## 7. Ranked recommendations

**P0 — actively harmful, fix first**
1. Credit injected learnings in `dev_complete_task` (§2.2) — stops active corpus
   degradation; also un-blocks promotion + fixes ranking inversion + defuses the
   scheduled-verification landmine.
2. Route `dev_complete_task` through `TestVerificationService` (§2.4) — without it, any
   autonomous drain records unverified claims; prerequisite for trusting everything else.

**P0 — live authorization hole, fix now**
3. Gate `resources/*`/`prompts/*`/`completion/complete` for instance principals at the
   dispatch level (§6.1) — today a zero-grant mTLS node reads every agent's system prompt.
   Small, self-contained patch.

**P0 — one-file wiring that completes already-approved lanes**
4. `REMEDIATION_APPLIERS["system.module_promotion_ready"]` → `ModulePromotionService.promote!` (§5).
5. `prompt_refinement` branch in `apply_recommendation!` (§4.2).
6. Sensor one-liners: `code_changes`→`code_change` + `.compact` ×3 + widen the pipeline
   rescue (§3.5, §3.6).

**P0 — absent vision pillars (larger, but each is one seam)**
7. MCP-client for platform agents — merge `McpServer` tools into `AgentToolBridgeService` (§6.3).
8. Cross-plane peer-capability-token arm in `McpTokenAuthentication` (§6.4) — the
   dev-plane-can't-reach-ops-hub gap.

**P1 — activate the dormant machinery**
6. Schedule `RalphLoopClosureService#execute_cycle` (§3.1) — the complete OODA cycle exists;
   this also revives goal advancement (§3.4).
7. Rewrite `SkillMutationService` onto the real schema (§4.1) + enable `skill_optimization`
   (§4.4) + KG-sync global skills (§4.3).
8. Fix the adaptation lane both halves: stamp/execute the diff plan (§3.2) and migrate its
   approval to `Ai::Approvals::Gateway` with a `GoalPlan` hook (§3.3).
9. Scheduled code-quality discovery driver (§2.1) — with 1+2 in place this closes the full
   self-improvement loop machine-end-to-end.
10. Semantic `query_learnings` (§2.3) — wiring only.

**P2 — completeness** (see per-section fingerprints): revert-throttle consumption,
knowledge retirement, skill attribution, capability taxonomy/registry, capability-scoped
verification, manifest verify: probes, recipe runner wiring, backup/DR skill, DB-driven
autonomy constraints, seed-slug validation, template audit trail (already approved).

## 8. Verification notes

Lead-session re-verification performed before inclusion (per
[[finding-confidence-tracks-prose-not-mechanism]] and [[feedback-grep-hit-is-not-a-code-reference]]):
- `execute_cycle` call-sites: monorepo grep → definitions + own spec only. Confirmed.
- `on_approval_decision` implementors: 5 models, `Ai::Agent` absent. Confirmed.
- `code_changes` vs `code_change`: both sides read. Confirmed.
- `.compact` in the three named sensors: zero occurrences. Confirmed.
- `recalculate_effectiveness!`: fires from `record_injection!` on every injection (tighter
  than reported); hard `0.0` math and promotion gate SQL both read. Confirmed.
- `checks_passed: true` hardcoded in `record_outcome`'s passed branch. Confirmed.
- `SkillMutationService` vs schema: `ai_skill_usage_records.outcome` (no `success`),
  `ai_skill_versions` lacks `version_number`/`status`. Confirmed.
- `apply_recommendation!` branch list read directly. Confirmed.
- Flipper auto-enable block read directly (only `skill_self_learning` +
  2 compound-learning flags). Confirmed.
- `ModulePromotionService`: 1 definition, 4 comments, 0 call-sites; no
  `module_promotion` applier entry. Confirmed.
- `query_learnings` strict-AND symptom reproduced live over MCP (multi-word → 0 results;
  single word → results).

Known items deliberately NOT re-filed: everything applied/approved in the 08-04→08-06
drains (per `list_improvements`), the instance-principal tier-skip policy fork, the
declarative module-authoring seam, campaign-approval-is-manual (design), and
mcp-executions-not-persisted (pinned decision).

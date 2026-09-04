# Model Routing Governance

Governed per-task model-tier + reasoning-effort routing (campaign `019f2163`, inc1–inc7):
every AI call resolves onto a 4-tier price ladder, any escalation above baseline must carry
a recorded, machine-auditable reason or fail closed to the cheaper tier, and the outcomes
feed back into both a benefit-measurement loop and durable platform knowledge. This is the
authoritative reference for that system; deep how-to lives in the code comments of the
files below — this doc is the map.

## The 4-tier price ladder

`Ai::ModelTiers` (`server/app/models/ai/model_tiers.rb`) is the single home for
capability-tier classification, ascending: `:light` (Haiku-class, ~$1/MTok in) →
`:standard` (Sonnet-class, ~$2-3/MTok) → `:reasoning` (Opus-class, ~$5/MTok) → `:frontier`
(Fable/Mythos-class, availability-gated, ~$10/MTok).

Classification is **floor-over-prefix**: a family-prefix table (`TIERS`) gives each known
model family a tier FLOOR. When a live `Ai::ModelPricing` row exists, its price band can
only *escalate* a known family above its floor — never demote it — so a stale/zero/cheap
price row can't misclassify a premium family downward, while a genuine price change
rebalances the tier with no deploy. Unknown families (no prefix match) are driven purely by
price, defaulting to `:standard` when no price is known. No hardcoded model names beyond
family prefixes (`[[no-hardcoded-ai-model-names]]`).

The 3-valued router/finops label vocabulary (`economy`/`standard`/`premium`) still exists at
the DB-enum layer (`Ai::TaskComplexityAssessment::RECOMMENDED_TIERS`) — `premium` folds both
`:reasoning` and `:frontier`; `ModelTiers.from_label` / `.to_label` convert between the two
vocabularies, with frontier admitted separately behind the Fable gate.

## Per-task governed routing

`Ai::Routing::TaskTierResolver` (`server/app/services/ai/routing/task_tier_resolver.rb`)
resolves ONE task-complexity classification (`TaskComplexityClassifierService
#classify_preview`, no DB write) into a target tier, a re-selected model, and a reasoning
effort, wrapped in a machine-auditable rationale hash. It is wired into both execution seams
(`Ai::Ralph::TaskExecutor#build_agent_options`,
`Ai::McpAgentExecutor::ProviderExecution#resolve_model_config`) and into bulk/background
callers via `AgentBackedService#resolve_task_tier`
(`server/app/services/concerns/agent_backed_service.rb`) — all three behind the same account
gate (below).

**Escalation must be justified, or it fails closed.** Any tier above `:standard`, or above
the agent's own baseline tier, requires a non-empty rationale (`escalation_justification`);
if the resolver would escalate without one it returns the cheaper baseline tier instead
(`kind: :fail_closed`). Downgrades (indicated tier below baseline) always proceed and record
a cheap rationale — cost-saving needs no justification bar. `expert` complexity mapping to
`:frontier` is never effort-substituted; a task assessed as needing frontier-class reasoning
gets a frontier model, not just more effort on a cheaper one.

**Pin semantics.** A model pin (`agent.mcp_metadata.model_config.model`, honored by
`Ai::Agent#resolved_model`) IS the articulable reason: the resolver fixes the tier at
baseline, no re-selection, no downgrade, no escalation. Downgrade/escalation re-selection
applies only to selector-chosen (unpinned) models. An operator can also pass an explicit
`operator_tier_pin` (tier name or `economy`/`standard`/`premium` label) that overrides the
complexity-indicated tier directly — `:frontier` is reachable only via an explicit
`:frontier`/`"frontier"` pin, never through the label vocabulary (which tops out at
`"premium"` ⇒ `:reasoning`).

**Effort-first policy.** Before jumping one rung to `:reasoning`, the resolver prefers
holding the baseline tier and raising reasoning effort instead — paying for a bigger model is
the outcome we most want to avoid when a cheaper lever (effort) is available. It substitutes
effort for tier ONLY when the baseline model is effort-capable
(`Ai::Llm::ModelCapabilities.supports_effort?`) AND the complexity score is below
`TaskTierResolver::ESCALATE_OVER_EFFORT_SCORE` (**0.60**). At or above that bar, or when the
baseline model can't take an effort param, it escalates the tier instead — and the rationale
records which branch fired and why. `:frontier` escalation is never effort-substituted
regardless of score.

**Frontier admission** additionally requires ALL of: the Fable gate ON
(`Ai::FableRouting.enabled_for?`), an allowlisted `agent_type`
(`AgentModelSelector.fable_preferred_agent_type?`), `expert` complexity OR an explicit
operator frontier pin, account budget headroom, and no active refusal pre-route for that
`(agent_type, category)`. Any missing condition caps the target to `:reasoning` (see
[fable5-compliance.md](fable5-compliance.md) for the Fable-specific rules this gate defers to).

Every resolution persists one `Ai::TaskComplexityAssessment` + one `Ai::RoutingDecision`
(linked bidirectionally) carrying the full rationale — best-effort, a persistence failure
never breaks the calling execution.

## The two settings keys

| Key | Governs | Default | Resolution |
|---|---|---|---|
| `ai_task_tier_routing_enabled` | Master per-task routing gate. OFF ⇒ `TaskTierResolver` is never called by any of the three seams — behavior is byte-identical to pre-inc2. ON ⇒ every governed call gets tier + effort resolution and a persisted rationale. | **OFF** | `Account#settings` → `SiteSetting` fallback → `false` (`TaskTierResolver.enabled_for?`, mirrors `Ai::FableRouting`'s reader) |
| `fable_routing_enabled` | Platform-side frontier (Fable/Mythos) candidacy for the platform's OWN model selection. OFF ⇒ Fable is excluded from the candidate set entirely — non-selectable by preference, UCB exploration, or cost tie. | **OFF** | `Ai::FableRouting.enabled_for?(account)`; operator flips ON only after platform Fable readiness (compliance, refusal-handling, budget guards — see [fable5-compliance.md](fable5-compliance.md)) |

Both gates are per-account settings with a site-wide fallback, both default OFF, and both are
independent: routing can be governed (`ai_task_tier_routing_enabled=true`) while frontier
stays unreachable (`fable_routing_enabled=false`) — `expert`-complexity tasks simply cap at
`:reasoning` until an operator explicitly turns Fable on.

## Benefit-measurement loop and advisory semantics

Three read endpoints (`GET /api/v1/ai/model_router/escalations`, `.../escalations/rollup`,
`.../escalations/benefit`, `Api::V1::Ai::ModelRouterAnalyticsController`, permission
`ai.routing.read`) surface governed decisions:
`Ai::ModelRouterService::RoutingAnalytics#escalation_decisions` (raw feed, filterable by
tier), `#escalation_rollup` (selection counts, top rationale categories, escalated spend
share + the benefit summary), `#escalation_benefit_deltas` (the controlled comparison).

The benefit comparison buckets governed `Ai::RoutingDecision` rows by `[task_type,
complexity_level]` (the controlled variable, read off the linked `TaskComplexityAssessment`),
then within each bucket compares the escalated cohort against the standard-tier cohort
(held/effort-substituted/downgraded to standard) on success rate, average cost, and average
latency. Success rate and cost are pooled; latency is **segmented by recording seam**
(`rationale.latency_seam`, tagged at `RoutingDecision#record_outcome!` time —
`agent_execution` = `AgentExecution#duration_ms`, `ralph_iteration` = whole-iteration
duration, `router_request` = routed request round-trip; untagged legacy rows fall into
`unknown`) because the seams measure different durations — latency deltas are computed per
seam and only for seams present in both cohorts (`avg_latency_delta_by_seam`).
Only buckets where BOTH cohorts have measured outcomes are pooled into the aggregate
summary — an unmatched bucket contributes to `total_buckets` but not `matched_buckets`, so a
lopsided sample can't skew the delta.

The `advisory` is **report-only, never auto-tunes**. `recommend_tightening` fires
(`status: "non_positive_benefit"`) only when the escalated cohort has at least
`BENEFIT_ADVISORY_MIN_DECISIONS` (**10**) measured outcomes AND the pooled success-rate delta
is non-positive (`delta <= 0`). Below that sample size the status is `"insufficient_data"`
(or `"insufficient_comparison_data"` / `"no_escalations"` when there's nothing to compare) —
a small window never triggers a false alarm. An operator (or a future automation with its own
governance) decides what to do with the advisory; the resolver itself does not read it back.

## CC / platform Fable decoupling

`Ai::ClaudeExport::AgentSkeletonSync` (`server/app/services/ai/claude_export/agent_skeleton_sync.rb`)
maps the `:frontier` tier to the Claude Code frontmatter `model: "fable"` **unconditionally**
— the tier comes from the agent's declared `model_requirements.tier` or `Ai::ModelTiers.classify`
over its pinned model (for an account's own export, over `agent.resolved_model`) — and this does NOT consult
`Ai::FableRouting.enabled_for?`. The platform-side gate governs whether the platform may
select Fable for its OWN executions; it says nothing about Claude Code, which carries its own
separate Fable/Mythos entitlement from the CC subscription tier. **Do not** "fix" this to
check `FableRouting` — that would incorrectly couple an unrelated platform kill-switch to the
CC-side model picker. This is the intentional decoupling: CC-side Fable skeletons emit `fable`
now; platform-side frontier candidacy stays behind its own gate.

Frontier/reasoning-tier skeletons also carry escalation guidance in their frontmatter
`description` (the delegation surface a caller reads before `Task()`-ing the agent) and, for
`:frontier`, an instruction in the body to state in one sentence why frontier capability is
required before starting — mirroring the tier resolver's own rationale-or-fail-closed
discipline on the CC side.

## Agent-sync usage

`rake claude:sync_agents` (`server/lib/tasks/claude_sync.rake`, wrapped by
`scripts/sync-claude-agents.sh`) regenerates the Claude Code subagent skeletons from platform
`Ai::Agent` records via `Ai::ClaudeExport::AgentSkeletonSync#sync!`. By default it exports the
**canonical** set (global, seeded agents) to `.claude/agents/powernode/*.md`, which **is
committed**: the files are slug-keyed and carry no per-install id, so they render the same on
every install, and `scripts/check-claude-agents-fresh.sh` (via `scripts/pattern-validation.sh`)
fails the gate when a seed or renderer change leaves them stale. `ACCOUNT_ID=<uuid>` exports an
account's *own* agents (clones, local agents) instead, to the gitignored
`.claude/agents/powernode-local/`; `TARGET_DIR=<path>` overrides the output directory (mainly
for tests). Each skeleton is a thin MCP bootstrap that fetches the agent's real system prompt
and skill context at spawn time (`platform_get_agent` by slug / `platform_get_skill_context`),
so editing the platform agent takes effect on the next spawn with no regeneration needed.
Idempotent: unchanged agents produce zero file writes; skeletons whose backing agent is no
longer syncable are removed (only files carrying the generated-file header are touched). Run
it after adding/renaming/retiering a platform agent so CC sessions can
`Agent(subagent_type: "<slug>")` it. The full skeleton contents, the `platform.route_task`
router shared with the Concierge, and the reverse `claude:import_agents` proposal path are in
[`guides/use-powernode-from-claude.md`](../../guides/use-powernode-from-claude.md#platform-agents-as-claude-code-subagents).

**Naming disambiguation** — two similarly named "Claude agent" surfaces point in opposite
directions and must not be confused. `server/db/seeds/claude_agents_seed.rb` seeds **platform**
`Ai::Agent` records INTO the database (provider-agnostic reasoning/analysis agents; "claude" in
the filename is legacy naming — the model is chosen at runtime by `Ai::AgentModelSelector`).
`Ai::ClaudeExport::AgentSkeletonSync` is the inverse: it **exports** those platform agents OUT of
the database as generated Claude Code subagent skeletons (committed for canonicals). Seeding creates the records
the exporter later reads; neither replaces the other, and a change to one is never a change to
the other.

## Learning feed-forward usage

`Ai::Learning::GuidancePromotionService#promote`
(`server/app/services/ai/learning/guidance_promotion_service.rb`) is the explicit PROMOTE
step: it turns a durable `CompoundLearning` (or ad-hoc content) into a `guidance-<slug>`
tagged `Ai::SharedKnowledge` entry, retrievable via `search_knowledge tag:guidance-*` and the
`dev_next_task` digest — the same recall path every executor already queries. Promotion is
**never automatic**; raw discoveries must earn their ranking through reuse first
(`Ai::Learning::RalphLearningExtractor`, `server/app/services/ai/learning/ralph_learning_extractor.rb`,
derives a bounded title, category, and calibrated importance from loop learnings so they're
consumable at all — the old shape was a null title + blanket 0.3 importance that nothing
could rank). `#promote` reuses `Ai::Guidance::GuidanceKnowledgeSeeder#upsert_guidance`'s
key-anchored upsert (`provenance->>'guidance_key'`), so re-promoting the same `slug` updates
the entry in place instead of duplicating it, and inherits the gate-#9 refusal for content
naming a private extension.

**Consumption signal**: `usage_count` on the resulting `SharedKnowledge` row, incremented on
the `search_knowledge` retrieval path — that's the measurable evidence a promoted guidance
entry is actually being read by executors, not just written once and forgotten.

## The intentional inc3 gate-OFF asymmetry

`Ai::Ralph::TaskExecutor#resolve_effort`
(`server/app/services/ai/ralph/task_executor.rb`) and
`Ai::McpAgentExecutor::ProviderExecution#resolve_model_config`
(`server/app/services/ai/mcp_agent_executor/provider_execution.rb`) treat the
`ai_task_tier_routing_enabled` gate differently ON PURPOSE:

- **Ralph (`TaskExecutor#build_agent_options`)** — when the gate is OFF, it falls through to
  the pre-inc2 baseline path, which still calls `EffortMapper.resolve` directly
  (`resolve_effort`). Effort is **live regardless of the gate** here — it's a quality
  improvement the operator wants on deploy, not something worth withholding behind the tier
  gate.
- **MCP executor seam (`ProviderExecution#resolve_model_config`)** — `effort` starts `nil` and
  is only ever set from `resolution.effort` inside the gate-ON branch. When the gate is OFF,
  no effort value is computed or forwarded at all — **fully gated**.

Both are correct for their seam; do not "fix" the asymmetry by adding an ungated
`EffortMapper.resolve` call to the MCP path, and do not gate Ralph's baseline effort call
behind `ai_task_tier_routing_enabled` — either change would silently alter live behavior on
an unrelated toggle.

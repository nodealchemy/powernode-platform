# Agent Orchestration & Enhancement — Campaign Findings & Remaining Work

**Date:** 2026-06-28
**Campaign:** System Agent Orchestration & Enhancement (`019f1054-…`)
**Status:** core enhancements landed STAGE-only on `campaign/019f1054-…`; the
larger architectural items below are recommendations awaiting operator approval.

This snapshots what the campaign delivered and the architecture findings that
exceed a single drain iteration — primarily the operator directives on
provider-agnostic agents, a model-discovery learning loop, agent
consolidation/reuse, and the **global-seeded-core vs project-custom** seam.

## Delivered (STAGE-only, test-first)

1. **GitOps Reconciler agent** — closed the one genuinely unowned domain. The
   reconciler attributed drift proposals to an arbitrary first account agent
   because the `"GitOps Reconciler"` it looked up was never seeded. Added the
   agent (+ persona, reasoning tier, policies, approval chain), wired
   `system.gitops.drift_detected` through the DecisionEngine (autonomous policy
   on Fleet Autonomy, per the sensor-gates-as-Fleet-Autonomy rule).
2. **Personas + model tiers** — added `system_prompt` to the 5 monitor agents
   that lacked one; added reasoning-tier `model_requirements` to the
   security/operator/topology/diff agents. Confirmed **no hardcoded model ids**
   in any system-agent seed.
3. **Provider-agnostic naming** — renamed `Claude Strategic Planner` →
   `Strategic Planner` and `Claude Research Analyst` → `Research Analyst`
   (names + slugs, idempotent in-place data-fix), de-provider-named their
   prompts. Unbound 8 system-infra skills wrongly `binds_to`'d to these generic
   core agents (domain purity); rebound Strategic Planner to its own planning
   skills.
4. **Model-discovery learning loop** — `Ai::AgentModelSelector` was purely
   greedy; added a deterministic UCB exploration term so under-sampled / newly
   added models get discovered and gather empirical signal, instead of the
   selector locking onto an early winner. ENV-tunable, never promotes a
   capability-incapable model.
5. **Visual Design Assistant** — reclassified `image_generator` →
   `content_generator` (it emits text/specs, not images) and dropped its
   `model_config.provider:'openai'` pin.

## Remaining work (recommendations — by priority/risk)

### R1 — Global-agent seam — APPROVED + IN PROGRESS (operator-directed 2026-06-28/29)

Operator directives received during the campaign: fundamental core/system agents
= GLOBAL (account_id nil), custom/clones = account-associated; agents
provider-agnostic; model-discovery learning loop; global = canonical/seed-managed
with audit logs; consumers CLONE to modify (globals read-only), maintainers own
globals; integrate with the EXISTING clone/reconcile/diff infra.

**DONE (committed STAGE-only):**
- **Phase 1 — foundation** (core): `Ai::Agent` mirrors `Ai::Skill` —
  `account_id` nullable + `source_key`/`cloned_from_id`/`source_version`/
  `source_snapshot`/`is_system`, `include GloballyScopable`, `resolve_for`
  (override-aware: account row wins over global), `resolving_account` for global
  model resolution. (67bcd278)
- **Phase 2 — system agents global** (submodule): all 8 system agents seed
  global (`find_or_initialize_global_agent`, in-place conversion, id stable);
  ~10 name-based resolvers + 2 policy seeds + skill-bindings flipped to
  `resolve_for`/`.global`. (a32f392)
- **Governance** (core): `agents_controller` wired into `GloballyScopedContent`
  (clone-to-customize, `update_from_source` rebase, read-only guard,
  `?scope`); `Ai::Agent` audit hook for canonical-global changes. (935b123d)

**DONE (the bounded, tested sweep — operator-directed):**
1. **Controller ID-resolver sweep (~62 sites) — COMPLETE.** All
   `<account>.ai_agents.find(id)` / `.find_by(id:)` resolve-existing sites
   flipped to `Ai::Agent.for_account(<account>.id)` across autonomy/policy
   (Chunk A) and conversation/skills/teams/memory/security/analytics/tools
   (Chunk B). These resolve an agent to use/inspect it; per-account config
   (trust/autonomy/policy keyed by agent_id+account_id) is untouched, so no
   read-only guard needed. Account create/list-own paths left account-scoped.
2. **Core platform operational agents → global (Chunk C) — DONE for concierge +
   the 7 utility agents.** `Ai::Agent.find_or_initialize_global(slug:)` +
   `resolve_concierge_for` (override-aware); `default_concierge` (×5) and
   `extraction_service` resolvers flipped.

**DONE — directive 8 complete.** All fundamental platform agents are now global:
- `Ai::Agent.find_or_create_global(slug:) { block }` helper.
- `monitoring_analytics` (4 monitors), `claude_agents` (Strategic Planner,
  Research Analyst), and the 3 fundamental `autonomy_data` agents (Infrastructure
  Health Monitor, Process Automation Optimizer, Visual Design Assistant) → global.
- Seed-side resolvers flipped (platform_skill_assignments / ai_teams /
  ai_governance / autonomy_data provider+trust+concierge) so the now-global
  agents are wired up override-aware.
- Industry/business example agents (Legal/Finance/Sales/Life-Sciences/Customer-
  Success) and demo team sets (ai_dev_team, ai_todo_team, ai_example_templates)
  stay account-scoped demo data — by design.

**Remaining (lower-priority follow-up):** multi-tenant — global agents currently
bind some account-scoped utility skills (fine in single-tenant core mode);
globalize those skills too for true multi-tenant.

### R1-LEGACY — original gap writeup (superseded by the above)

The operator's principle — *"core functionality should be built-in seeded
GLOBAL agent/prompt/skill combos; custom projects may need custom agent
infrastructure"* — is satisfied for **skills** but **not for agents**:

| | Skills | Agents |
|---|---|---|
| `account_id` nullable (global rows) | ✅ `schema.rb` (ai_skills) | ❌ `NOT NULL` (ai_agents) |
| `source_key` upsert / `is_system` | ✅ | ❌ none |
| `GloballyScopable` (`global`/`for_account`) | ✅ included | ❌ not included |
| Seeded as global baseline | ✅ baseline tier | ❌ demo-tier, account-scoped instances |
| Project/workspace ownership | ❌ none | ❌ none |

**Recommendation:** mirror the skills model for agents — nullable `account_id`
+ `source_key` (+ `is_system`/`is_global`), include `GloballyScopable`,
`for_account` scope = `account_id IN (id, NULL)`, move core agent seeds from the
demo tier to the baseline tier with `account_id: nil`. **Risk:** broad — every
agent query that assumes account scoping (resolution, concierge, teams) must
switch to `for_account`, and name/slug uniqueness must handle global-vs-account
collisions. This is a dedicated initiative with a migration + a query-site
sweep, not a drain increment. A separate `project_id`/`workspace_id` ownership
dimension (for "custom projects … custom agent infrastructure") is also absent
for both models and would be a second, additive seam.

### R2 — Dynamic-creation provider-agnosticism (MEDIUM).

- `Ai::ConciergeService#create_agent_from_spec` is selector-driven (good) but
  persists only the **resolved** model (`mcp_metadata.model_config.model`),
  pinning the agent to one model at creation — it won't re-resolve by tier later
  (unlike seeded agents, which persist `model_requirements`). Recommend
  persisting `model_requirements` (tier) and not hard-pinning the model, so
  dynamically-created agents keep benefiting from the learning loop.
- The design-time helper LLM in `DesignAgentTeamFromIntentExecutor`
  (`:131,:139`) and `DesignSkillFromIntentExecutor` (`:25,:132,:168`) hardcodes
  `provider_type: "openai"` + a `gpt-4o-mini` fallback. Make these
  provider-agnostic (account default provider / selector).

### R3 — Agent consolidation (MEDIUM; touches shared seeds + team assembly).

- **Knowledge Graph Curator** is defined twice with conflicting `agent_type`
  (`ai_utility_agents_seed.rb` `assistant` vs `ai_dev_team_seed.rb`
  `data_analyst`); the dev-team copy is dead (the utility seed creates the row
  first) and carries hardcoded model ids that never apply. Collapse to one
  source of truth.
- **Visual Design Assistant / Process Automation Optimizer / Infrastructure
  Health Monitor** are each defined in two seed files. Pick one owning seed.
- `System Health Monitor` vs `Infrastructure Health Monitor` overlap — review
  for merge.
- Demo dev-team (`ai_dev_team_seed`) vs todo-team (`ai_todo_team_seed`) are
  near-identical; keep one canonical template.

### R4 — Disk Image Manager skills (MEDIUM; net-new executors).

Disk Image Manager has 0 bound skills — no disk-image skill executors exist
yet. Giving it skills means creating executors (promote / rollback / retention)
wrapping the existing publication services + `Ai::Skill` rows + `binds_to`,
then the bindings seed materializes them. Larger than a drain increment because
it's net-new capability, not a binding tweak.

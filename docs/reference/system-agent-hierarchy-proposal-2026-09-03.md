# System agent hierarchy — consolidation and gap-fill proposal (2026-09-03)

Operator request (17:58 UTC): the Autonomy page shows only standalone agents with no lineage and no
delegation policies, several `data_analyst` agents look duplicated, and the system extension needs
agents for every role it governs — skills, prompts, delegation, and the ability to autonomously
design, improve and implement teams and graphs.

This document is the discovery result and the proposed campaign. Nothing below is implemented.

## 1. What is actually there (verified on ops-hub and in code)

**Live data (ops-hub, one account, 2026-09-03 18:10 UTC):** 29 agents — 23 global platform agents
(`account_id NULL`, `is_system`) and 6 demo account agents. Every one is `trust_level: supervised`
with `parent_agent_id NULL`. `ai_agent_lineages`: 0 rows. `ai_delegation_policies`: 0 rows.
`ai_agent_teams`: 0 rows. Intervention policies by owner: Fleet Autonomy 70, SDWAN Manager 43,
Runtime Manager 7, Disk Image Manager 6, CVE Responder 5, GitOps Reconciler 3, operator-only 80.

**Why the page says "standalone".** The lineage forest treats every agent without an
`ai_agent_lineages` row as an orphan (`autonomy_controller.rb:71-73`), and the only writer of that
table, `Ai::Agents::FactoryService#create_lineage`, has no production caller. The page's copy says
lineage "is created when agents are organized into team hierarchies", but team membership writes no
lineage row either. Two further defects: global agents are invisible to the forest (it reads
`current_account.ai_agents`, which excludes `account_id NULL`) while the picker lists them via
account-scoped trust scores; and the single-agent endpoint returns `{agent_id, children, parents}`
where the tree expects `{id, name, type, status}`, so selecting an agent renders a nameless node.

**Why "multiple data_analyst".** There is no duplicate-creation bug: every seed is keyed. The tree
labels nodes by `agent_type`, and seven distinct agents carry `data_analyst` (Research Analyst,
System Analytics Intelligence, RAG Query Engine, RAG Reranker, and the three demo industry
analysts). One real collision exists: Knowledge Graph Curator is seeded twice — global `assistant`
(`ai_utility_agents_seed.rb`) and account-scoped `data_analyst` (`ai_dev_team_seed.rb:545`).

**Delegation.** `Ai::DelegationPolicy` has a model, REST CRUD and a React panel, and zero rows
anywhere. `DelegationAuthorityService#validate_delegation` therefore returns `allowed: true` for
every delegator; its only enforcement site is `AgentManagementTool#spawn_task`. The model validates
`agent_id` unique globally although the table and controller are account-scoped. No MCP tool reads
or writes delegation policies.

**Responsibility surface of the extension** (`PolicyDeclarations::POLICY_SETS`, 14 sets + manual):
Fleet Autonomy owns 4 of the 8 agent-keyed sets and, inside its own 56-key set, the topology,
ingress, storage, packages, architecture and gitops-drift domains — 70 of 134 agent-scoped
policies. (Figures as of the 18:10 discovery; Phase 2A since moved 16 rows to their owners and regrouped
the rest, see `PolicyDeclarations` for the live census.) Six sets plus the manual set are operator-only (`agent_key: nil`, ~54 policies).
System Concierge (24 skills) and System Topology Designer (8 skills) carry no policies; Disk Image
Manager (6 policies) and GitOps Reconciler (3) bind no skills. `system.sdwan_federation_compose` is
registered but declared in no set.

**What already exists to build on.** `Ai::AgentLineage` (with cycle/self checks), `Ai::DelegationPolicy`,
`Ai::AgentTeam` (topology/strategy vocab, roles), `Ai::TeamTemplate`, `Ai::AgentProposal`,
`Ai::ImprovementRecommendation` types `team_composition | skill_consolidation | prompt_refinement |
skill_creation | capability_gap`, the discover → approve → dev-improve loop, `SelfImprovementTool`
(mutate/evolve/compose skills), `TeamManagementTool` / `CoordinationTool` (create/optimize teams),
`AgentManagementTool` (create/update agents, spawn_task), the seeded skills "Design Agent Team From
Intent", "AI Agent Architect", "Agent Autonomy", "Skill Manager", and the 2026-06-28 campaign's
global-agent seam (`source_key`, `resolve_for`, `GloballyScopable`). There is no agent-graph model;
"graph" today means the knowledge graph or a DAG execution.

## 2. Proposal

### Principles
- Reuse first: every mechanism above is wired, not replaced. New code is seeds, one lineage/delegation
  writer seam, one meta-agent, one sensor, and UI truthfulness fixes.
- Authority never flows laterally: every autonomous design change is an `Ai::AgentProposal` or
  campaign proposal until an operator approves; new agents start `supervised` with a delegation
  policy that forbids delegating what they were not granted (the permission-laundering rule).
- Seeds are the source of truth for the hierarchy (global, `source_key`-managed, audited); the
  runtime creation paths write the same lineage rows so the picture stays true.

### Phase 0 — make the page truthful (small, ships first)
1. Lineage forest reads `Ai::Agent.for_account(account.id)` so global agents appear; nodes render
   name first and type second; "Standalone Agents" becomes "Root agents (no parent)".
2. Single-agent lineage returns a tree node; the picker and the tree agree.
3. `Ai::DelegationPolicy` uniqueness becomes `(agent_id, account_id)`; a `platform.describe_delegation`
   / `platform.set_delegation_policy` pair (read `ai.agents.read`, write `ai.agents.update`, gated) so
   agents can see and propose their own authority.
4. Drop the dev-team demo duplicate of Knowledge Graph Curator.

### Phase 1 — hierarchy, lineage and delegation as seeded data
Root/coordinator: **System Concierge** (already the routing agent with 24 skills) becomes the
manager of a seeded hierarchical team "System Operations" and the lineage parent of every domain
agent. A `System::Seeds::HierarchyWriter` seam writes `parent_agent_id`, the `Ai::AgentLineage`
row (`spawn_reason: seed`) and the `Ai::DelegationPolicy` row for each agent; the same seam is called
from `AgentManagementTool#create_agent`, `AgentAutonomyService#create_agent_for_team` and
`create_team_from_spec`, so runtime-created agents get lineage too.
Delegation policies per agent: inheritance `conservative`, `max_depth` 2, budget share from the
existing agent budget. Concierge: `moderate`, depth 3, may delegate to any system agent.

> **Superseded (as built).** This proposal originally set `allowed_delegate_types` = "the agent's
> own domain executors" and `allowed_actions` = its policy set's categories. Both columns are read
> in a different vocabulary: `allowed_delegate_types` is compared against `Ai::Agent#agent_type`
> (`Ai::DelegationPolicy#allows_delegate_type?`, called from
> `Ai::Autonomy::DelegationAuthorityService` and from `Ai::Routing::AgentRouterService`, which
> filters its candidate pool with it), and `delegatable_actions` against a task's `action_type`.
> Writing skill slugs or policy categories there would refuse every delegation and empty every
> router pool rather than scope them. As built, a domain agent is a leaf with an empty list and
> `max_depth` 2 as the operative brake — see
> `extensions/system/server/app/services/system/governance/hierarchy_reconciler.rb`.

### Phase 1b — share canonical agents with Claude Code (operator direction 18:30 UTC)
"Seamlessly use platform agents within Claude Code and natively within the platform." The base
exists: `Ai::ClaudeExport::AgentSkeletonSync` + `rake claude:sync_agents` write thin subagent
skeletons to `.claude/agents/powernode/<slug>.md` that fetch the live prompt and skill context over
MCP at spawn time, so the platform stays the source of truth. As of 18:30, before this increment, it
had never run on a checkout, its output was gitignored, it embedded the per-install agent UUID, and
it carried no tools or delegation. (All four are addressed below: `.gitignore` now ignores only
`.claude/agents/powernode-local/`, the committed skeletons are slug-keyed and carry no UUID, and
they carry a `tools:` allowlist and a Delegation section.)
The increment: slug-keyed, environment-independent skeletons for the CANONICAL set, committed and
kept fresh by a `check-claude-agents-fresh.sh` gate (same shape as the MCP catalog check); a
`tools:` allowlist derived from the agent's tool families; the delegation policy and lineage parent
rendered in the body; SessionStart shows the count, a Stop hook regenerates after seed edits; and the
reverse path `rake claude:import_agents` turns a hand-authored Claude Code agent into an
`Ai::AgentProposal` (never a direct create — canonical rule). Skills as `SKILL.md` follow later.
Automatic delegation (operator direction 18:35): each exported description is a routing description
("Use this agent when … / Do not use for …", derived from skills and policy domains) so Claude Code's
Agent tool picks the right subagent by itself, and one router — the existing
`Ai::Routing::AgentRouterService`, exposed as `platform.route_task` and wired into the Concierge's
delegation path — ranks the same canonical set for both Claude Code and the platform, honouring
delegation policies.

### Phase 1c — Claude Code runs feed the platform's statistics (operator direction 19:00 UTC)
Statistics come only from `Ai::AgentExecution` rows (trust evaluation on completion,
`record_model_performance` → `Ai::AgentModelPerformance` → `AgentModelSelector`), all written by the
platform's own executor. A new `platform.record_agent_execution` verb mints one such row for a Claude
Code run of a platform agent, attributed to the session's `mcp_client` identity and idempotent on a
run key; a `SubagentStop` hook reports automatically with the skeleton's own self-report as fallback.
Boundary: a Claude Code run counts toward model statistics and trust, never toward autonomy budgets or
consent ceilings; Claude Code-only models never become platform routing candidates.

### Phase 2 — split responsibilities so every domain has an owner
New global agents (seed + prompt + approval chain + policy set with `agent_key` + trust bootstrap +
`binds_to` aliases), each carved from `FLEET_AUTONOMY_POLICIES` or from an operator-only set:

| Agent | Takes over | Policies | Skills to bind (existing executors) |
|---|---|---|---|
| Capacity Manager | provisioning (6), instance-pool agent (8) + operator (4), platform-scaling (2), cordon (1), node-lifecycle manual verbs | ~21 | provision/replace/reap/drain/scale/cordon executors, Platform Resilience |
| Storage Manager | storage (2), volume-snapshot operator (1), restore/copy-swap | ~4 | restore_volume, snapshot executors, storage owner/migration |
| Ingress Manager | ingress (4: expose_service_*, acme_certificate_*), service backends | ~5 | expose_service_* executors, ACME, scale_project backends |
| Supply Chain Manager | packages (3) + architecture (4) | 7 | package_module_*, architecture_* executors |
| System Topology Designer (existing) | topology domain (3 incl. the undeclared `sdwan_federation_compose`) | 3 | its 8 skills |
| Disk Image Manager (existing) | unchanged | 6 | NEW: promote / rollback / retention executors (R4 of the 2026-06-28 campaign) |
| GitOps Reconciler (existing) | unchanged + `system.gitops_drift_remediate` moves here from Fleet Autonomy | 4 | NEW alias + sync/apply/register executors |

Fleet Autonomy keeps the fleet sensors' core (cert, module, instance health, task) — roughly 25
policies — and becomes what its name says. Operator-only sets stay (they are the human caller's
verbs) but each now has an agent twin where a sensor exists, so `by_agent_pivot` has no empty domain.
SDWAN Manager is already right-sized. Reference counts, FLEET_SENSORS.md, the Autonomy modal's
`SYSTEM_AGENT_NAMES`, `AGENT_IDENTITIES` and `AGENT_ALIASES` all move with the split; the
governance reconciler carries existing installs across.

### Phase 3 — autonomous design / improve / implement
New governance meta-agent **Platform Architect** (`is_governance: true`, child of System Concierge)
bound to: AI Agent Architect, Design Agent Team From Intent, Skill Manager, Agent Autonomy, the
SelfImprovementTool and ImprovementTool actions, CampaignTool. Its loop:
1. **Sense** — a `GovernanceGapSensor` on the Fleet Autonomy tick emits `system.governance_gap`
   signals for: a declared category with no agent set, an agent with policies but no skills, a
   sensor bound to `skill: nil`, an executor with no seed row, a team whose manager has no lineage
   edge, a delegation policy missing for an active agent. (Every one of these is a finding this
   audit made by hand.)
2. **Propose** — the DecisionEngine routes the signal to Platform Architect, which files an
   `Ai::ImprovementRecommendation` of type `capability_gap` / `team_composition` /
   `skill_creation` / `prompt_refinement` with a concrete spec (agent, team, skill or prompt diff).
   Policy: `system.governance.propose` = auto_approve (the offer IS the human gate).
3. **Implement** — on operator approval the offer becomes a dev-improve task (code/seed changes) or
   a runtime materialisation through the existing tools (`create_agent`, `create_team_from_spec`,
   `set_delegation_policy`, `mutate_skill`) under `system.governance.materialize` = require_approval.
   Prompt changes go through `Ai::SkillVersion` / the agent's `source_version` so they are diffable
   and revertible; nothing edits a global in place without an audit row.
4. **Verify** — the sensor clears when the gap closes; the recommendation scoreboard records it.

### Phase 2b — the Engineering hierarchy (operator direction 18:20 UTC)
The operator's second directive: maintain a comprehensive suite of agents, skills and teams for
research, development, system/infrastructure management, SDWAN, modules, services and related
features, for both fully autonomous and supervised operation, supporting the platform's own design,
development and build responsibilities. Operations (above) covers running the fleet; this track
covers building the platform. Both hang under System Concierge; Platform Architect (Phase 3) is the
Engineering team's manager.

| Role | Agent (existing → reuse; NEW → seed) | Skills / tools | Loop it drives |
|---|---|---|---|
| Research | Research Analyst, Strategic Planner (existing) | web/knowledge research, tech-radar sweep, `query_learnings`, `create_knowledge` | weekly tech-radar → knowledge entries + `capability_gap` offers |
| Product / spec | PRD Generator (existing) | spec-driven plan (Specify → Plan → Tasks) | turns an approved offer into a campaign proposal with increments |
| Architecture | Platform Architect (NEW, Phase 3) + System Topology Designer | AI Agent Architect, Design Agent Team From Intent, architecture catalog verbs | designs agents/teams/graphs/skills; owns this document's successors |
| Development | Platform Developer (NEW, `code_assistant`) — the platform_agent driver for dev-improve | Extension Developer, code_semantic_search, dev_next_task/dev_complete_task, campaign tools | drains dev-improve autonomously under the loop guardrails; Claude Code stays the default executor, this agent is the always-on one |
| Review / QA | LLM Judge + System Quality Assurance (existing) | code-review dimensions, test-gap, `platform_verify` | independent review of every drained task before dev_complete_task |
| Build & Release | Release Manager (NEW, `monitor`) | `system_dispatch_module_build_batch`, `promote_module_version`, `rollback_module_version`, disk-image publish/revert, `module_publication_integrity`, catalog freshness | builds on a merged develop, walks the promotion ladder, verifies by digest, holds on core/extension skew (the 2026-08 outage class) |
| Documentation | Documentation Specialist (existing demo agent → promote to global) | docs accuracy specs, runbook/tutorial upkeep | keeps docs, FLEET_SENSORS.md and the MCP catalog truthful after every landed change |
| Knowledge | Knowledge Graph Curator (existing global) | KG curation, learnings lifecycle | consolidates learnings from every lane into platform knowledge |

Policy sets: a new `engineering` set (agent_key per agent) with categories `dev.task_claim`,
`dev.task_complete`, `dev.campaign_propose` (auto_approve — proposals are the gate),
`release.build_dispatch` (auto_approve on develop), `release.promote` / `release.rollback` /
`release.deploy_platform` (require_approval until trust ≥ trusted and never for the control plane
itself), `docs.update` (auto_approve). Delegation: Platform Architect may delegate to every
Engineering agent; Platform Developer may delegate review to LLM Judge only; Release Manager
delegates to nobody.

Teams: "Platform Engineering" (hierarchical; manager Platform Architect) and "System Operations"
(hierarchical; manager System Concierge). Both seeded as `Ai::TeamTemplate`s with lineage edges,
so a graph of the whole organisation renders on the Autonomy page.

### Phase 4 — teams and graphs
- Seed the "System Operations" hierarchical team (manager System Concierge, members = the domain
  agents with roles `manager|specialist|executor`), and an `Ai::TeamTemplate` for it, so team,
  lineage and delegation are three views of one structure.
- Agent graphs: no new model. A "graph" is a `TeamTemplate` (nodes) plus delegation policies
  (edges) plus a `Ai::DagExecution` when run; the Platform Architect designs graphs by proposing a
  TeamTemplate. Revisit a dedicated model only if a use case needs edges the template cannot express.

## 3. Sizing and order
Phase 0: ~8 files, one lane, ~1 day. Phase 1: ~10 files (seam + seeds + specs), one lane after
Phase 0. Phase 2: ~4 lanes (one per new agent + the two existing-agent skill lanes), each
~8-15 files; the reference-count specs and reconciler make this safe to land incrementally. Phase 3:
sensor + meta-agent seed + two policy declarations + tool wiring, ~12 files, after Phase 2.
Phase 2b: ~5 lanes (one per new/promoted agent, plus the engineering policy set and team templates). Phase 4: seeds only. Every phase deploys with the same recipe as batches 5-8.

## 4. Decisions needed from the operator
1. Root: System Concierge as the coordinator of both hierarchies (recommended) vs a new dedicated
   root agent.
2. The Operations split as tabled (four new agents) vs fewer (e.g. fold Storage + Ingress into one
   "Services Manager").
3. Operator-only sets: give each an agent twin (recommended) vs leave them operator-only.
4. Authority: propose-only under `require_approval` for every materialisation and every release
   promotion (recommended) vs allowing `auto_approve` for skill/prompt refinements and develop
   builds on trusted agents.
5. Engineering executor: Platform Developer as a platform_agent driver for dev-improve alongside
   Claude Code (recommended) vs Claude Code only, with the platform agents limited to research,
   review, release and docs.

## 5. Operator rulings (2026-09-03 18:12 UTC)
1. Root: **System Concierge** coordinates both hierarchies.
2. Operations split: **four new managers** (Capacity, Storage, Ingress, Supply Chain) **and an agent
   twin for every operator-only set** where a sensor exists.
3. Authority: **skill and prompt refinements auto-approve on trusted agents**; structural changes
   (agents, teams, delegation, promotion, deploy) stay `require_approval`.
4. **Platform Developer** drives dev-improve as a platform_agent alongside Claude Code.
5. **Canonical rule:** every official agent is a seeded canonical — global (`account_id NULL`),
   `source_key`-managed, `is_system`, read-only through the API (the `GloballyScopedContent`
   read-only guard and the architecture-catalog `is_canonical` precedent). New agents are created
   only as clones of a canonical into an account (`cloned_from_id`, `source_version`,
   `update_from_source` rebase), with lineage written at clone time. Consequences for the plan:
   the demo account agents are either promoted to canonical (Documentation Specialist) or left as
   demo data outside the hierarchy; `AgentManagementTool#create_agent` gains a required
   `canonical_slug` (or `template`) and refuses a free-form agent unless the caller holds
   `ai.agents.manage`; `find_or_initialize_global_agent`'s adopt-a-stray behaviour is replaced by
   an explicit conflict error so an operator clone is never silently converted into a canonical.

6. **Driver ruling 2026-09-03 23:45 (self-improvement readers).** `Ai::Learning::TrajectoryAnalyzer`
   and `Ai::SelfImprovement::SkillMutationService` deliberately read only the account's OWN skills and
   therefore see no global canonical skill (HIER-P2G made the system skills global). That is the
   canonical rule applied to skills: an account never mutates a canonical in place; it clones and
   refines the clone, and a canonical itself is refined only through the Platform Architect's
   versioned path (Phase 3, `Ai::SkillVersion`, auto-approved on trusted agents per ruling 3). The
   existing spec that pins "ignores shared system skills" stays.
7. **Driver ruling 2026-09-03 23:20 (single-writer seeds).** `PolicyReconciler` is the only writer of
   declared intervention-policy rows; agent seeds write identity, prompt, chain, trust, tool access and
   skills. Legacy seeds that still upsert rows are rewritten under offer 01a0696f once approved.

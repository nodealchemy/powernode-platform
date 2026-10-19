# Streamlining review — 2026-10-19

> **Status:** review report (audit = report only). Nothing here was executed, claimed, approved or
> changed in code. The work is filed on the control-plane hub as **campaign proposals** (status `proposed`)
> for the operator to review and launch; proposal ids are listed in §8. Deployment-specific names are
> placeholders (`<ops-hub>`, `<dev-host>`); the real values live in platform knowledge (`deployment-*` tags).
>
> Evidence sources: `platform_campaign_list`, `platform_campaign_list_proposals` (26 rows, all read),
> `platform_dev_list_tasks dev-improve` (queue summary + newest 200 of 1,137 tasks read),
> `platform_list_improvements` (51 pending, all read), `platform_governance_dashboard`,
> `platform_list_governance_reports`, `platform_list_agents`, `platform_list_teams`, `platform_list_skills`
> (3 pages, all 128), `platform_list_intervention_policies` (100 rows returned, the verb's cap),
> `platform_list_ralph_loops`, `platform_knowledge_health`, `platform_search_knowledge`, the first page
> (60 of 179) of today's audit log, and `grep`/`wc` over the working tree. `platform_code_dead_code` and
> `platform_code_find_duplicates` were dispatched to the worker but their result keys were still `null` when
> this report was written; the code-level bloat figures below are therefore `wc`/`grep` counts, not analyzer
> output, and the two scans should be re-read before the dead-code task in §7 is launched.

## 1. Status summary

| Surface | Count | Reading |
|---|---|---|
| Campaigns | 22 (14 completed, 7 `active`, 1 completed at 97%) | **All 7 active campaigns are at 0% with no activity since 2026-09-19** (30 days): 41 tasks parked, no driver lease. Six of the 14 "completed" campaigns completed with `total_tasks: 0` — closed as superseded, not delivered. |
| Ralph loops | 23 | 1 real driver (`dev-improve`, iteration 1,162 / 1,500 cap, 2 concurrent claims). 7 campaign loops `pending`, 1 `running` with 1 iteration, 14 paused/completed/cancelled. `dev-improve` hits `max_iterations` in ~340 iterations. |
| `dev-improve` queue | 1,137 tasks | 1,089 passed, 0 pending, 0 in progress, 11 blocked, 7 skipped (all skipped on 2026-08-05). Queue is **drained**; the loop is idle. |
| Pending improvement offers | 51 | 12 are one serialised plan (`Housekeeping N/12`, all `scripts/wt.sh` lane/landing work); ~25 are `followup|…` critic residues of landed IMPs; 3 are security (sensitive-params, autonomy-gate params, skill-envelope error text); 1 compliance P1 (GDPR export never downloadable). |
| Campaign proposals | 26 | 4 `proposed` (2 GDPR discovery findings, "Harness eval loop", "Proving ground"), 4 `rejected` (3 August bulk-drain proposals, 1 nft atomic apply), 18 `spawned`. **The 22 `[fresh-install #N]` proposals are not in this queue** — they are `Ai::AgentProposal` rows (`create_proposal`), listable only over REST (`GET /api/v1/ai/.../proposals`); there is no MCP list verb and `create_proposal` writes no audit row. |
| Agents (active) | 41 | 28 canonicals + **13 `Claude Code (headersHelper) #1…#13`** mcp_client identities all minted today (the #14 OAuth workaround registers a new client per token refresh and `McpClientIdentityService` mints a fresh `#N` each time no orphaned agent is in grace). |
| Teams | 2 | Platform Engineering (10), System Operations (12). |
| Skills | 128 | ~70 `system-*` extension skills, ~43 core generic, 10 account-scoped RAG/utility, `usage_count: 0` on every row returned. |
| Intervention policies | 100 (cap) | **Engineering rows are duplicated 2–3×** (see §3.5): the four engineering canonicals carry 40 rows where 18 are distinct, including a `release.promote` pair that is `auto_approve` and `require_approval` at the same priority. Three `scope: global` `notify_and_proceed` rows exist for `release.deploy_platform`, `release.rollback`, `release.promote` (p50), which contradicts `platform-engineering-agents.md` ("every other release verb has no floor"). |
| Governance | 39 open reports, 0 critical | 30 `resource_abuse` + 4 `anomaly` + 5 `policy_violation`, all `warning`, minted every 6 h since 2026-09-27 against Platform Developer, Fleet Autonomy and Release Manager; 4 "agents under investigation". None resolved. No `system.governance_gap` signals active. 0 pending deferred operations. |
| Knowledge | 6,395 entries | **6,386 (99.9%) `stale_count`**, 102 rated; 1,659 learnings (1,496 active, 25 verified); graph 132,664 nodes. The dev-mTLS procedure exists **8×** identical (`source_learning_id 019e6ca3-…`, created 2026-07-03…07-19 at 2–4 day intervals) — the learning→knowledge importer is not idempotent (fresh-install #17). |
| Reference docs | — | `CLAUDE.md` and `use-powernode-from-claude.md` link `docs/reference/auto/todo.md`; the file does not exist (`docs/reference/auto/` holds `manifest.yml`, `mcp-tools.md`, `README.md`). |

**In flight:** nothing is executing. `dev-improve` is drained; no campaign holds a driver lease.
**Stale:** 7 active campaigns (30 days, 0%), 39 governance reports, 12 Housekeeping offers (16 days).
**Duplicated:** mcp_client agents (13), intervention policies (22 surplus rows), knowledge entries (7 surplus copies of at least one procedure), `provision_ci_worker` vs `system_provision_ci_worker`.
**Abandoned:** 6 "completed" campaigns with 0 tasks; 3 rejected bulk-drain proposals from August; 7 skipped tasks from 2026-08-05.

## 2. Backlog classification

Recommendations only — nothing was dismissed, edited or rejected.

### 2.1 Campaigns (22)

| Campaign | Status | Recommendation |
|---|---|---|
| LLM symbol summaries (disjoint-vocabulary retrieval gap) | active, 0/6 | **keep** — discovery quality; fold into C3 (discovery layer) as a later increment |
| Per-node agent scratch tmpfs size override | active, 0/5 | **blocked-by-streamlining** — fleet-extension feature; park until C4 names the Fleet Operator owner |
| Session observations feed the learning store | active, 0/7 | **merge** into C6 (knowledge cleanup): importer idempotency must land first or it multiplies the duplicate class |
| Context ledger and manifest-derived subagent tool grants | active, 0/6 | **keep — promote**: this *is* the per-task grant half of the discovery architecture (§4.3); re-home under C3 |
| Core-purity baseline burn-down | active, 1 running | **keep** — independent hygiene; unaffected by the roster change |
| Render-helper positional arguments | active, 0/3 | **keep** (small, mechanical) — fold into C7 as a seed/code pruning increment |
| MCP runner: per-account gVisor MCP execution | active, 0/13 | **blocked-by-streamlining** — 13 tasks of new surface; decide after C5 fixes the tool-surface target |
| Frontend consolidation | completed 97% (38/39) | **keep closed**; the 1 unfinished task should be re-filed as an offer, not re-opened |
| Component status plane | completed 79% (80/101, 3 failed) | **keep closed**; the 3 failed tasks are already in the pending offers as `followup|…` |
| 6 campaigns completed with 0 tasks (One front door, Federated prod plane, Agents that know the fleet, SDWAN test fabric, No bare facts, Project owns its template, Improvement backlog drain, Package currency) | completed | **obsolete** as campaigns — their objectives survive as docs under `docs/reference/*-design-2026-09-*.md`; C6 archives those |
| Environment as a first-class noun; Retire task-dispatch spine; System agent hierarchy; Autonomous Project Platform; Autonomous Project Operations | completed 83–100% | **keep closed** |

### 2.2 Campaign proposals (26)

| Proposal | Status | Recommendation |
|---|---|---|
| GDPR: no safeguard against anonymising sole owner (01a0bc71-3b25) | proposed | **keep** — needs the operator policy decision it names; not streamlining |
| GDPR: OAuth refresh-token residue survives erasure (01a0bc71-1ac5) | proposed | **merge** with the pending `COMPLIANCE: GDPR export never downloadable` offer and the `GDPR deletion follow-ups` offer into one compliance campaign (outside this review's scope; listed in C8) |
| Harness eval loop with evidence-attached promotions (01a0b0bb) | proposed | **blocked-by-streamlining** — evaluates agents; wait for the 4-agent roster |
| Proving ground (01a07058) | proposed | **obsolete** as proposed (presumes the 20+ agent catalogue); re-propose against the survivors |
| 3 × "Drain N improvement recommendations" (Aug) + nft atomic apply | rejected | **obsolete** — leave rejected |
| 18 spawned | spawned | follow the campaign row above |

### 2.3 Pending improvement offers (51)

| Group | Count | Recommendation |
|---|---|---|
| `Housekeeping 1/12 … 12/12` (wt.sh lanes, sweep, land.sh) | 12 | **merge** into one campaign (C8 names it); approve individually inside it, never batch |
| `codify\|dev-loop\|wt-land-verify-scripts-unreferenced` + `Housekeeping 8/12` | 2 | **merge** (same fix: wire scripts into the dev-loop skill) |
| Security: `sensitive-params-filter-text`, `autonomy-gate params unfiltered`, `skill-result-envelope error unredacted`, `approval-execution events raw error`, `Task log_tail unredacted`, 2 × `agent log_tail clipped key` | 7 | **keep** — security; drain first, independent of streamlining |
| Compliance: GDPR export never downloadable (P1), GDPR deletion follow-ups, erasure server/worker | 4 | **keep** — compliance; merge with the two GDPR proposals (C8) |
| GitOps follow-ups (4), ACME/disclosure sweeps (2), SMB (2), storage FK (2), module-build attribution (3), machine-park metering (2), int4 overflow (1), MCP stdio follow-ups (2) | 20 | **keep** as `followup` residue — these are the Platform Engineer's normal diet once `dev-improve` is re-filled; none blocks streamlining |
| `Stuck-remediation escalations re-mint approval every ~5h` | 1 | **keep — raise priority**: same noise class as the 39 open governance reports (§1) |
| `Extension services credit compound learnings without citation` | 1 | **merge** into C6 |
| `Codified lane scripts unused`, `prepare-extension-test-db silent exit`, `extension module images no build marker`, `public-mirror leak sweep`, `no_bare_fact lint red` | 5 | **keep** — tooling correctness |
| `Template unassign purges node assignments: mark destructive` | 1 | **keep** — safety annotation; relevant to C5 (destructive hints are what tool scoping keys on) |

### 2.4 Fresh-install findings (22, filed as `[fresh-install #N]` agent proposals)

All 22 are **kept** and folded into campaigns rather than re-filed: #1–#5, #7–#13 → C1; #6, #18–#22 → C2; #14, #15, #16 → C9; #17 → C6. No duplicate proposal was created for any of them.

### 2.5 `dev-improve` tasks

11 blocked + 7 skipped (2026-08-05, `IMP-b602…`, `IMP-6cd6…`, `IMP-a834…`, `IMP-7e8e…`, `IMP-8175…`, `IMP-8e1c…`, `IMP-70d8…`): **obsolete** — 75 days old, their source offers have since been re-discovered as newer fingerprints; recommend `dev_update_task` to `skipped` with a reason once the operator confirms (18 items → bulk-op confirmation applies).

## 3. Bloat inventory (measured)

### 3.1 Agents and teams

- **28 canonical agents** across 5 seed files + 11 extension seeds: 10 Engineering (Architect, Developer, Release Manager, Documentation Specialist, Research Analyst, Strategic Planner, PRD Generator, LLM Judge, System QA, Knowledge Graph Curator), 2 concierges (Powernode Assistant, System Concierge), 11 fleet operations (Fleet Autonomy, SDWAN, Disk Image, GitOps, Runtime, Topology Designer, Capacity, Storage, Ingress, Supply Chain, CVE Responder), 5 vertical demo personas (Customer Success, Legal & Compliance, Life Sciences Research, Finance Operations, Sales Operations) seeded in core mode.
- `server/db/seeds/ai_utility_agents_seed.rb` (666 lines) defines **20 more** agent specs (RAG Reranker, RAG Query Engine, Intent Classifier, Code Review, …) of which only PRD Generator / LLM Judge / KG Curator appear in the live list — the rest are dormant definitions.
- Each canonical ships: a persona prompt (the four engineering prompts alone are ~400 of the seed's 618 lines), a `tool_families` list (20–40 names each, hand-maintained), 1 approval chain, 2–7 policy rows, a trust score, lineage edges, a delegation policy, a team-template role, and a Claude Code skeleton under `.claude/agents/powernode/` (24 files). Every retired agent removes all nine artefacts.
- **Tool-family lists are already stale**: Platform Developer lists `dev_list_tasks`, `campaign`, `code` (prefix families) and 6 Gitea verbs; the Documentation Specialist's `docs.update` category gates **nothing** (documented in `platform-engineering-agents.md`).
- Governance declarations: `extensions/system/.../governance/policy_declarations.rb` is **1,780 lines**; `decision_engine.rb` declares **35 lanes** with 9 distinct `owner:` keys (sdwan-manager 15, capacity-manager 7, storage-manager 3, cve-responder 2, supply-chain-manager / platform-architect / gitops-reconciler / disk-image-manager 1 each). **46 sensors** and **68 skill executors** in the system extension.
- Teams: 2 canonical teams that are projections of the same hierarchy (the doc itself calls it "one structure, three views"); `CanonicalTeamReconciler` exists only to keep the three views agreeing.

### 3.2 MCP tool surface

- **674 actions across 79 tool classes** (`docs/reference/auto/mcp-tools.md`, generated 2026-10-02). `platform_list_skills` with the MCP prefix reports 681 names in the live client (extension deltas since generation).
- By namespace: `system_*` 211 + `system_sdwan_*` 85 (= 44% of the surface, from 2 classes: `SystemFleetTool` 161 actions, `SdwanTool` 87), `docker_*` 52, `data_source_*` 29, `code_*` 17, `campaign_*` 16, `dev_*` 6, `kubernetes_*` 5.
- By verb: `list_` 94, `get_` 77, `create_` 50, `delete_` 42, `update_` 41 — **304 of 674 (45%) are generic CRUD verbs** on ~90 nouns. `readOnlyHint: true` 275 / `false` 399.
- **440 of 674 actions render under "Uncategorized"** in the catalog generator (`server/lib/tasks/mcp_tool_catalog.rake:179` maps class → category from registry *comments*; the `system_*` and `code_*` classes have none). There is no declared family on `declare_action`; `tool_families` scoping (`AgentToolBridgeService#scope_to_tool_families`) and `ToolRelevanceFilter` both match by **name prefix**, and a 0-match **fails open to the full registry** (documented in `claude_export/tool_allowlist.rb`).
- Exact duplicates / near-duplicates: `provision_ci_worker` ↔ `system_provision_ci_worker`; `system_blast_radius` ↔ `code_blast_radius`; `system_runbook_generate` ↔ `system_cve_runbook_generate` ↔ `get_runbook`; `create_proposal` ↔ `campaign_propose` ↔ `propose_feature` ↔ `system_propose_architecture`; `system_recent_signals` ↔ `perceive_signals` ↔ `recent_events` ↔ `get_activity_feed`; `health` ↔ `get_system_health` ↔ `integration_health` ↔ `system_platform_health_check` ↔ `docker_cluster_health` ↔ `data_source_health` ↔ `knowledge_health` ↔ `skill_health`; `system_cancel_task` ↔ `system_abort_task`; `wait_for_task` ↔ `system_wait_for`; 8 × `discover_*`.
- `platform.health` and `platform.recent_events` returned `{"result": null}` on this hub during the review — two of the four generic health/event verbs do not answer.
- Code: `server/app/services/ai/tools/` = 82 files / **30,686 lines**; `base_tool.rb` 2,248, `data_source_tool.rb` 1,936, `dev_loop_tool.rb` 1,696, `agent_autonomy_tool.rb` 1,257, `platform_api_tool_registry.rb` 1,045, `mcp_platform_tool_registrar.rb` 927.

### 3.3 Skills, prompt templates, seeds

- 128 skills, every one `usage_count: 0`. ~15 are non-platform verticals shipped in core (Finance Analyst, Sales Intelligence, Legal Assistant, Bio Research, Marketing Suite, Customer Support, Content Localization, User Research, Product Management, Productivity Assistant, Compliance Review, Brutally Honest Mentor, Devil's Advocate, Extended Thinking, Content Research). ~70 `system-*` skills are 1:1 wrappers of executors already exposed as MCP actions (e.g. `system-acme-certificate-provision` ↔ `system_acme_provision_certificate`).
- Core seeds: **39 files / 12,564 lines**; extension seeds **85 files / 16,199 lines**. Only **4 core seed files are demo-gated** (`Seeds.demo?`); the 1,145-line `ai_dev_team_seed.rb`, 785-line `ai_todo_team_seed.rb`, 666-line `ai_utility_agents_seed.rb`, the 5 vertical personas and `comprehensive_ai_providers_seed.rb` (hard-coded demo account, fresh-install #6) all run in core mode.
- `ai_skills_seed.rb` 897 lines / 23 skills; `ai_system_prompt_templates_seed.rb` 10 templates; `platform_skill_assignments_seed.rb` 137 lines of agent→skill bindings that duplicate what `SkillBindings` derives from executors in the extension.
- `.claude/skills/` 13 skills (`audit bootstrap campaign cleanup commit deploy dev-loop fix-tests gen-tests improve powernode verify workspace`), `.claude/loops/` 3, `.claude/hooks/` 30 scripts.

### 3.4 Docs

- 168 Markdown files / 62,525 lines under `docs/`; `docs/operations/` alone 69 files / 19,071 lines of which **31 are dated one-offs** (7 `platform-autonomy-dryrun-run-2026080*`, 5 `rcp-p*`, 4 `*-evaluation-2026-*`, 3 `*-audit-*`, `*-design-2026-*`, `*-findings`), plus 17 dated design/gap-map files in `docs/reference/`. Extension docs: 92 files.
- `docs/reference/auto/todo.md` is linked from `CLAUDE.md` and the Claude guide but **does not exist** (dead reference; the `Dead Reference Cleanup` rule applies).
- `docs/reference/auto/mcp-tools.md` is 9,505 lines and 17 days stale against the live catalog.

### 3.5 Governance rows

From the 100 policy rows returned (the verb's cap; the true count is higher):

| Agent | Rows | Distinct (category, verdict, priority) | Surplus |
|---|---|---|---|
| Platform Architect | 16 | 6 | 10 |
| Platform Developer | 14 | 7 | 7 |
| Release Manager | 8 | 4 | 4 (and `release.promote` carries **both** `auto_approve` and `require_approval` at p10) |
| Documentation Specialist | 2 | 1 | 1 |

The duplicates have three id prefixes (`01a06bba-…`, `01a06d3c-…`, `01a0701f-…`) = three seed runs; `engineering_upsert_policy` in `ai_engineering_agents_seed.rb` is not keyed the way the rows were first written. The same non-idempotency class as #17.

### 3.6 Knowledge

- 6,386 / 6,395 shared-knowledge entries flagged stale; 102 rated.
- Dev-mTLS procedure imported 8× (ids `019f2667-81c7`, `019f308a-62cb`, `019f3c8e-8f22`, `019f46db-479a`, `019f5128-2635`, `019f59bd-49a5`, `019f6409-f778`, `019f7a5b-0f13`), all `provenance.source_learning_id = 019e6ca3-b9c8-73b4-8100-4489844268f0`. The 8 copies have 8 different `quality_score`s and share `usage_count`, so recall ranks copies against each other.
- Graph 132,664 nodes / 132,251 edges; 4,267 low-confidence; `event_processed_24h: 0`.

### 3.7 Code (grep-level)

`server/app` 1,548 Ruby files / 330,342 lines; `server/app/services/ai` 588 files / 147,822 lines (45% of the server); 164 `Ai::*` models; `worker/app` 288 files; `frontend/src` 1,527 TS/TSX files; 1,566 spec files. Analyzer-based dead-code and clone figures: pending (see header).

## 4. Target agent roster and discovery architecture

### 4.1 Roster: 4 canonical agents

| Survivor | Charter | Absorbs | Why it survives |
|---|---|---|---|
| **Powernode Concierge** | The one conversational front door: onboarding, provisioning briefs, routing any request to a skill or to another survivor via `route_task`; never executes fleet or code writes itself. | Powernode Assistant, System Concierge | Users need exactly one door; both current concierges are already resolved through `AccountPrincipalResolver.concierge_for`. Depends on provider/model resolution being correct (C2). |
| **Platform Engineer** | Everything that changes the platform's own code, docs, release artefacts and knowledge: `platform_agent` driver for `campaign_delegate`, drains `dev-improve`, proposes campaigns, dispatches builds and walks the promotion ladder, keeps docs and the catalog truthful, consolidates learnings. Roles become **skills** (`engineer-develop`, `engineer-release`, `engineer-docs`, `engineer-research`, `engineer-curate`) selected per task via `discover_skills`. | Platform Architect, Platform Developer, Release Manager, Documentation Specialist, Research Analyst, Strategic Planner, PRD Generator, Knowledge Graph Curator | Categories `dev.*`, `release.*`, `docs.*` are per-*category* rows, so one owner carries all of them unchanged; `PLATFORM_AGENT_DEFAULT_SLUG` and `CORE_CANONICAL_KEYS` each point at one key. |
| **Fleet Operator** | Sole owner of every autonomy lane (35 `SIGNAL_BINDINGS`, 46 sensors, 68 executors): sense → decide → gate → act, per the existing per-category intervention policies. Domain expertise lives in the bound `system-*` skills, not in nine personas. | Fleet Autonomy, Capacity, Storage, Ingress, SDWAN, Runtime, Disk Image, GitOps Reconciler, Supply Chain, CVE Responder, System Topology Designer | `SkillBindings::AGENT_ALIASES` already maps executor labels → source keys, so re-targeting is an alias-table change; `PolicyReconciler` re-homes rows by key. |
| **Platform Reviewer** | Independent review of every drained task and every autonomy decision above `monitored`; read-only tool scope (bootstrap verbs + `code_*` reads + `get_*`); never shares a conversation with the executor it reviews. | LLM Judge, System Quality Assurance | Separation of duties is a safety property, not bloat: the dev-loop skill forbids self-review. Keeping it as a distinct principal keeps the `canonical_principal` and audit seams honest. **Operator decision:** collapse to 3 by making review a skill run under the Concierge's principal — cheaper, weaker. |

Not agents: Claude Code sessions (mcp_client identities — keep, but fix the `#N` proliferation), fleet instances (mTLS principals), the 5 vertical demo personas (move to a `Seeds.demo?`-gated seed or to the marketing/supply-chain extensions), the 20 dormant utility specs (delete).

Net: 28 → 4 canonicals, 2 teams → 1 (Platform Engineering with Concierge as lead, or none: a 4-agent forest does not need a team template), 24 Claude skeletons → 4, 9 lane-owner keys → 1.

### 4.2 Discovery infrastructure that already exists (reuse first)

| Layer | Exists today | File |
|---|---|---|
| Always-on floor | `BootstrapVerbs::ACTIONS` — 8 read-only verbs every agent gets whatever its scope: `get_agent discover_skills get_skill_context search_knowledge query_learnings code_semantic_search describe_tool route_task` | `server/app/services/ai/tools/bootstrap_verbs.rb` |
| One-line catalog + on-demand schema | `tools/list` carries the first sentence (`LIST_DESCRIPTION_LIMIT = 160`); `platform.describe_tool` returns the full entry and `nearest` names, scoped like `tools/list` | `server/app/services/mcp/tool_catalog.rb`, `tools/tool_catalog_tool.rb` |
| Skill discovery | `discover_skills(task_context, mode: auto\|manifest, token_budget)` — embedding seeds + graph expansion under a token budget; `get_skill_context` | `server/app/services/ai/skill_graph/traversal_service.rb` |
| Semantic tool discovery | `SemanticToolDiscoveryService#discover(query, capabilities)` — embeddings over every registered tool, cached 6 h, dynamic-tool registration | `server/app/services/ai/tools/semantic_tool_discovery_service.rb` — **not exposed as an MCP verb** |
| Per-call relevance | `ToolRelevanceFilter` — keyword intent → prefix allowlist → cap (built for the 158-tool Concierge) | `server/app/services/ai/tool_relevance_filter.rb` |
| Scope resolution | `tool_access.enabled / allowed_tools / full_registry / tool_families`, SiteSetting `ai_agent_tool_family_defaults` per agent type; `ToolAllowlist` mirrors it for Claude skeletons | `agent_tool_bridge_service.rb#scope_to_tool_families`, `claude_export/tool_allowlist.rb` |
| Routing | `route_task` → `AgentRouterService` (capability 0.25, trust 0.2, skill 0.2, domain, performance, cost) | `server/app/services/ai/routing/agent_router_service.rb` |
| Knowledge | `search_knowledge` tag `guidance-*`, `query_learnings`, `search_knowledge_graph` | — |
| Drift detection | `GovernanceGapSensor` (owner-less category, skill-less policy set, lane bound to nothing, `tool_families` naming nothing) | extension |

### 4.3 Gaps the survivors need closed

1. **A declared tool taxonomy.** Families are name prefixes; 440/674 actions are uncategorised; a 0-match scope fails open. Add `family:` (and `noun:`) to `declare_action`, generate catalog sections, `tool_families` scoping, `ToolRelevanceFilter` intents and `GovernanceGapSensor`'s `tool_families` check from that one declaration.
2. **`platform.discover_tools(query, family?, read_only?)`** — expose `SemanticToolDiscoveryService` as a bootstrap verb so a survivor finds verbs by intent, then `describe_tool`s only the one it will call. Today an agent must either know the exact name or scan 674 one-liners.
3. **Per-task grants instead of per-agent lists.** `tool_access.tool_families` becomes a *ceiling*; the working set for a task is derived from the skill manifests `discover_skills` returns plus the lane's category, leased for the task and recorded (this is campaign 01a0baeb-0d79 "Context ledger and manifest-derived subagent tool grants", re-homed). Fails **closed** to the bootstrap floor, never open.
4. **Skill manifests as the unit of capability.** Every `system-*` skill already wraps one executor; give each skill a `tool_manifest` (verbs, knowledge tags, gate category) so `discover_skills(mode: manifest)` is complete and a survivor's capability is the union of its bound skills — the `platform_skill_assignments_seed.rb` and `SkillBindings` duplicates collapse into one source.
5. **Lane → skill → principal.** `SIGNAL_BINDINGS.owner:` names an agent key. Make it name a *skill* (the executor it already binds) and resolve the acting principal through `route_task`/`AccountPrincipalResolver` at tick time, so retiring an agent cannot orphan a lane and the `GovernanceGapSensor` "owner-less lane" class disappears structurally.
6. **A proposal list verb.** `create_proposal` has no `list_proposals` MCP twin and no audit row; the 22 fresh-install proposals are invisible to an agent. Add the read verb (or route `create_proposal` into the campaign queue).
7. **Knowledge recall hygiene** — duplicates (#17) and 99.9% stale flags crowd `search_knowledge`, which is tier 1 of the protocol below.

### 4.4 The survivor's progressive-disclosure protocol

```
tier 0  bootstrap floor (8 verbs, always present)
tier 1  discover_skills(task) → bound skill manifests (verbs + knowledge tags + gate category)
        discover_tools(query, family) → ≤10 ranked verbs with one-line summaries
        search_knowledge tag:guidance-* / query_learnings
tier 2  describe_tool(name) → full schema, annotations (readOnlyHint/destructiveHint), gate notes — only for the verb about to be called
tier 3  call under the task grant; gated verbs park via AutonomyGate exactly as today; record_agent_execution
```

The context cost per task is the floor plus the manifests actually discovered, not a 40-name family list in every prompt; a survivor can take any duty whose skill exists, which is what makes 4 agents sufficient.

## 5. Migration and retirement plan

Sequenced; each step is a campaign increment in §7 with a spec first.

1. **Freeze**: pause the 7 zero-progress campaign loops (`schedule_paused`), leave `dev-improve` as the single driver; no new canonicals.
2. **Discovery layer (C3)** lands first: declared families, `discover_tools`, per-task grants, skill manifests, lane→skill resolution. Survivors cannot work without it.
3. **Provider/model resolution (C2)**: real provider seeded in core mode, routable-provider filter, model catalogue validated — every survivor's `model: null` row resolves through this.
4. **Create the 4 survivors as new canonicals** (`source_key`s `powernode-concierge`, `platform-engineer`, `fleet-operator`, `platform-reviewer`) beside the old ones; bind skills by manifest; seed policies **idempotently** (one row per (agent, category, verdict, priority); fix the engineering upsert key; add a uniqueness constraint or a reconcile-time dedupe).
5. **Re-home**: `PLATFORM_AGENT_DEFAULT_SLUG` → `platform-engineer`; `CORE_CANONICAL_KEYS`, `AGENT_IDENTITIES`, `SkillBindings::AGENT_ALIASES` (old labels → new keys, so legacy executors keep resolving); `SIGNAL_BINDINGS.owner:` → skill; `PolicyReconciler` moves agent-scoped rows by key; approval chains renamed; `AccountPrincipalResolver` clones mint on first use (HIER-P2I unchanged).
6. **Shadow period** (one `dev-improve` drain + one fleet tick cycle) with old canonicals `is_enabled: false` but present, `GovernanceGapSensor` quiet, `CanonicalTeamReconciler` drift = 0.
7. **Retire**: `retire_by_predicate` on the 24 old canonicals (count stated: 24 agents + 13 mcp_client duplicates → operator confirmation per the bulk rule), `rails claude:sync_agents` regenerates 4 skeletons, delete the 20 dormant utility specs and the 5 vertical personas from core seeds, drop the team template or reduce to one.
8. **Docs**: `platform-engineering-agents.md`, `canonical-teams.md`, `agents-and-autonomy.md`, the governance runbook, `CLAUDE.md` driver sentence, Claude guide — rewritten for 4 agents; the ruling record (`system-agent-hierarchy-proposal-2026-09-03.md`) kept as history with a superseded banner.

## 6. Risks

| Risk | Mitigation |
|---|---|
| **Autonomy lanes lose owners** mid-migration — a lane whose `owner:` names a retired key resolves to nothing and the tick silently skips it | Lane→skill resolution (C3-5) lands *before* any retirement; `GovernanceGapSensor` already emits `owner-less lane`; add a boot-time hard fail in `system:governance:reconcile` when any lane resolves to no enabled principal |
| **Reaper incident class (fresh-install #16)** — the Fleet Operator inherits `system.abandoned_instance_reap` **`auto_approve`** at `monitored` (row `01a0bb88-f1b4`, today on Capacity Manager) | C9 lands the sensor fix (provider `running` ⇒ approval; hub self-silence suppresses the lane; persistent-home guests always approve; snapshot before terminate) and the row is seeded `require_approval` on the new owner; the migration never copies an `auto_approve` destructive row without re-review |
| **Policy specificity flip** — agent-scoped rows outrank global; while both old and new owners exist the gate may resolve the *old* agent's row | Shadow period with old agents disabled, not deleted; `PolicyReconciler` asserts one owner per category |
| **Three undocumented global `notify_and_proceed` floors on `release.deploy_platform/rollback/promote`** (p50) let a row-less MCP principal deploy or roll back the control plane with a notification | Flag now; C4 deletes or converts them to `require_approval` (operator decision — they may be deliberate for `<ops-hub>`) |
| **Self-review** if the Reviewer is collapsed to 3 agents | Keep the Reviewer, or require a distinct conversation + `canonical_principal` check per review |
| **Loss of the Platform Developer identity** that `campaign_delegate` and the dev-loop guardrails name | Alias `platform-developer` → `platform-engineer` in `AGENT_ALIASES` and `PLATFORM_AGENT_DEFAULT_SLUG` for one release; spec pins both resolve to the same row |
| **Tool-surface reduction breaks external clients** that hard-code names | Keep names as `ACTION_ALIASES` for one release with a deprecation note in `describe_tool`; the catalog generator lists aliases |
| **Bulk operations**: 24 retirements, 13 agent deletions, 22 surplus policy rows, 7+ knowledge duplicates, 31 doc moves, 18 task status changes | Every count is stated in the task; >5 items requires explicit operator confirmation; nothing batch-approved |
| Non-idempotent seeds re-create what was pruned on the next `db:seed` | Idempotency specs (C7-1) land before any pruning |

## 7. Proposed campaign / task breakdown

Nine campaign proposals, all `decision_authority: supervised`, `suggested_driver: claude_code`; tasks are the `plan_increments` of each proposal. Every code task is spec-first; "verification" names the gate (`scripts/validate.sh` targeted subset).

### C1 — Fresh install: plain-host developer path (fresh-install #1–#5, #7–#13)
Depends on: nothing. Blocks: nothing.
1. `WorkerCertManager#ssl_options` returns no client cert for `http://` backends / dev without PKI (#1) — spec: dev env + http URL + no PKI dir ⇒ no `Errno::ENOENT`; `BackendApiClient` stops opening the connection in `initialize`. Files: `worker/app/services/worker_cert_manager.rb`, `worker/app/services/backend_api_client.rb`.
2. Generate `worker/.session.key` on first boot or from `SIDEKIQ_WEB_SESSION_SECRET` (#2). Files: `worker/config.ru`, installer configs.
3. `powernode-installer.sh install --user` writes secrets toolchain-agnostically; `WORKER_ID` resolved from the backend or written by the installer after `Setup::FirstAdminService` (#3, #4). Files: `scripts/systemd/powernode-installer.sh`, `powernode-bootstrap.sh`, `server/app/services/setup/first_admin_service.rb`.
4. Re-dump core `schema.rb`; gate check `schema version ≥ newest migration` in `scripts/validate.sh` (#7).
5. Remove `VITE_API_BASE_URL`/`VITE_WS_BASE_URL` from `frontend-default.conf`; `manage-proxy-hosts.sh` refreshes the Vite allowed-hosts cache (#8, #9).
6. Installer detects mise/asdf/rbenv and writes `environment.d`; runtime pins derived from `.ruby-version`/`.node-version` (#10, #11).
7. Docs: quickstart wizard + one-time token, prerequisites, `database.yml` step, gitleaks pin (#5, #12, #13).
Acceptance: the "install recipe that worked" in `fresh-install-findings-2026-10-19.md` shrinks to `installer → db:setup → start → wizard`.

### C2 — LLM provider and model resolution in core mode (fresh-install #6, #18–#22)
Depends on: nothing. Blocks: C4 (every survivor's model resolves through this).
1. Replace `comprehensive_ai_providers_seed.rb`'s demo-account lookup with `Account.first`/wizard admin or `Seeds.demo?` gating; seed one real routable provider shell in core mode (#6). Spec: core-mode seed leaves ≥1 `is_active`, routable provider and prints no `❌`.
2. Server-side `routable` flag on `Ai::Provider`; `/ai/providers` excludes the `claude-code` recording scope by default; backend refuses credentials on non-routable scopes; `onboardingApi.createAiProvider` stops reusing `items[0]` (#18). Spec: a wizard credential never lands on `claude-code`; concierge start never 412s on a routable provider.
3. `default_model` becomes a select from the provider's synced models, validated server-side (#19).
4. Model catalogue: prefer the provider's live models endpoint; one maintained fallback list; remove non-existent ids (#20). Note: this review ran as `claude-fable-5-1`; the fallback list must be checked against the provider, not this report.
5. Persist wizard state server-side (account setup metadata) so `/onboarding/complete` never posts `provider_credential_id: nil` (#21).
6. `ProvisioningPage.tsx:71,75` surfaces the backend `error` with a link to provider settings (#22).

### C3 — Discovery layer: declared tool families, `discover_tools`, per-task grants, lane→skill
Depends on: nothing. Blocks: C4, C5.
1. `declare_action … family:, noun:` on `BaseTool`; registry exposes `families`; spec: every registered action declares a family (the lint that keeps 440 "Uncategorized" from returning). Files: `tools/base_tool.rb`, `platform_api_tool_registry.rb`, `mcp_platform_tool_registrar.rb`.
2. Catalog generator, `tool_families` scoping, `ToolRelevanceFilter` intents and `GovernanceGapSensor`'s `tool_families` check read the declared family; a 0-match scope **fails closed** to `BootstrapVerbs`. Spec pins the fail-closed rule in bridge and `ToolAllowlist`.
3. `platform.discover_tools(query, family?, read_only?)` over `SemanticToolDiscoveryService`; added to `BootstrapVerbs::ACTIONS` (read-only by contract spec). Files: new `tools/tool_discovery_tool.rb`, `bootstrap_verbs.rb`.
4. Skill `tool_manifest` (verbs, knowledge tags, gate category) on `Ai::Skill`; `discover_skills(mode: manifest)` returns it; `system-*` skills populate it from their executor's `skill_descriptor`. Collapse `platform_skill_assignments_seed.rb` into `SkillBindings`.
5. Per-task grant: `AgentToolBridgeService` derives the working set from discovered manifests + lane category within the agent's `tool_families` ceiling; grant recorded on the execution (re-home campaign 01a0baeb-0d79's 6 tasks here).
6. `SIGNAL_BINDINGS.owner:` accepts a skill key; `FleetAutonomyService#for_owner` resolves principal via `route_task`/`AccountPrincipalResolver`; `system:governance:reconcile` fails on an owner-less lane.
7. `platform.list_proposals` MCP read verb for `Ai::AgentProposal`; `create_proposal` writes an audit row.
8. (later) campaign 01a0bafb-d8f5 "LLM symbol summaries" as retrieval-quality increment.

### C4 — Agent consolidation: 28 canonicals → 4
Depends on: C3 (1–6), C2. Blocks: C7 (agent seeds), docs in C6.
1. Idempotent policy seeding: `engineering_upsert_policy` keyed on (agent, category, verdict, priority); DB uniqueness or reconcile-time dedupe; spec: seeding twice yields one row per key. Report the 22 surplus rows and the `release.promote` conflict for operator dedupe (bulk op: 22 rows).
2. Seed the 4 survivors (`powernode-concierge`, `platform-engineer`, `fleet-operator`, `platform-reviewer`) with manifests, policies, chains, trust; role prompts become skills. Files: new `ai_canonical_agents_seed.rb` replacing `ai_engineering_agents_seed.rb` + `ai_concierge_seed.rb` + extension agent seeds.
3. Re-home identities: `PLATFORM_AGENT_DEFAULT_SLUG`, `CORE_CANONICAL_KEYS`, `AGENT_IDENTITIES`, `SkillBindings::AGENT_ALIASES` (legacy labels → new keys), `ai_agent_hierarchy_seed.rb`, `ai_canonical_teams_seed.rb` (one team or none), `ClaudeExport::ToolAllowlist` rules by agent type. Spec: `campaign_delegate platform_agent` resolves to the Platform Engineer clone; every lane resolves to an enabled principal.
4. `McpClientIdentityService`: reuse by OAuth client **name + user** rather than minting `#N` per registration; cap and GC orphaned mcp_client agents (13 today; bulk op). Files: `server/app/services/ai/mcp_client_identity_service.rb`, `api/v1/oauth/registrations_controller.rb`.
5. Review and re-seed destructive lane verdicts on the Fleet Operator: `system.abandoned_instance_reap` and `system.pool_guest_reap` from `auto_approve` to `require_approval` pending C9; decide the three global `release.*` `notify_and_proceed` floors (operator decision).
6. Shadow period checklist, then `retire_by_predicate` on 24 canonicals (count stated; operator-confirmed), `claude:sync_agents`, remove 20 dormant utility specs and 5 vertical personas from core seeds (or demo-gate them).
7. Governance noise: the 6-hourly `resource_abuse` reporter and the ~5 h approval re-mint (pending offer `approval-noise|stuck-escalation-remint-cadence`) — dedupe per (agent, condition) and auto-resolve on recovery; resolve the 39 open reports (bulk op; operator-confirmed).

### C5 — MCP tool-surface reduction (674 → ≤350 advertised names, every one in a declared family)
Depends on: C3-1. Blocks: C6 catalog regeneration.
1. Delete exact duplicates (`provision_ci_worker` vs `system_provision_ci_worker`; `system_cancel_task` vs `system_abort_task`; `wait_for_task` vs `system_wait_for`) with `ACTION_ALIASES` for one release.
2. Merge the health family (8 verbs) into `platform.health(scope:)` and the signal/event family (4 verbs) into `platform.recent_events(source:)`; fix the two that return `result: null` today.
3. Collapse `system_sdwan_*` (85) and the `docker_*` (52) CRUD into noun-resource tools with `action:` + declared `destructiveHint` per action (the registrar already dispatches by action; this changes advertisement, not execution) — advertise ~25 and ~15 names respectively.
4. Fold `create_proposal` / `propose_feature` / `system_propose_architecture` into the campaign-proposal queue or one `propose(kind:)` verb.
5. Demote write verbs that are 1:1 with a `system-*` skill behind `execute_skill` where the skill carries the gate (the ~70 wrapper skills), keeping the read verbs advertised.
6. Regenerate `mcp-tools.md` (no "Uncategorized" section; alias table) and add a catalog-size gate (`validate.sh` fails above the agreed ceiling).

### C6 — Knowledge and docs cleanup (fresh-install #17)
Depends on: C4 for agent docs; otherwise independent.
1. Learning→knowledge importer upserts on `source_learning_id` (#17); spec: importing the same learning twice yields one entry. Files: the compound-learning import service / worker job.
2. One-off dedupe of existing copies (7 surplus for `019e6ca3-…`; query for all `provenance.source_learning_id` groups >1 and state the count before deleting — bulk op, operator-confirmed); merge `usage_count`/ratings onto the survivor.
3. Stale-flag recomputation or threshold fix: 6,386 / 6,395 stale is a scoring defect, not a corpus state.
4. Fold campaign 01a0baeb-317a "Session observations feed the learning store" here (after 1).
5. Pending offer `learning-credit|extension-direct-record_injection_outcome` (citation records).
6. Docs: move the 31 dated one-offs in `docs/operations/` and 17 in `docs/reference/` to `docs/operations/history/` and `docs/reference/history/` with an index; fix the dead `docs/reference/auto/todo.md` reference in `CLAUDE.md` and `use-powernode-from-claude.md` (or regenerate it); regenerate `mcp-tools.md`; rewrite `platform-engineering-agents.md`, `canonical-teams.md`, `agents-and-autonomy.md`, the governance runbook and the Claude guide for 4 agents, with a superseded banner on the 2026-09-03 ruling record.

### C7 — Seed and skill pruning
Depends on: C4-1 (idempotency first). 
1. Seed idempotency specs for every core seed file (`db:seed` twice ⇒ no new rows) before any pruning; the policy and knowledge duplicate classes are the motivating evidence.
2. Demo-gate or delete: `ai_dev_team_seed.rb` (1,145 lines), `ai_todo_team_seed.rb` (785), `ai_utility_agents_seed.rb` (666), the 5 vertical personas, `comprehensive_ai_providers_seed.rb` demo branch (after C2-1), `claude_agents_seed.rb` if superseded by `claude:sync_agents`.
3. Move ~15 vertical skills (Finance, Sales, Legal, Bio, Marketing, Customer Support, Localization, User Research, Product Management, Productivity, Compliance Review, the three reasoning personas, Content Research) out of core `ai_skills_seed.rb` into the marketing/supply-chain extensions or a demo-gated file; keep platform skills only.
4. Replace ~70 `system-*` wrapper skills' hand-written descriptors with `tool_manifest` derived from the executor (after C3-4) — same count, generated not maintained.
5. Fold campaign 01a0baea-e7b4 "Render-helper positional arguments" (3 tasks) as mechanical cleanup.
6. Re-read `platform_code_dead_code` / `platform_code_find_duplicates` results (`read_shared_memory` keys `code_intel.dead_code.powernode/powernode-platform`, `code_intel.find_duplicates.powernode/powernode-platform`) and file the verified candidates as individual offers — never auto-apply.

### C8 — Backlog hygiene (operator-decision heavy)
Depends on: nothing; best run first as a one-sitting triage.
1. Close or re-scope the 7 zero-progress active campaigns per §2.1 (`campaign_stop` with summary; the two re-homed ones move their tasks under C3/C6).
2. Approve the 12 `Housekeeping N/12` offers into one campaign (individually, in order; `wt.sh` first).
3. Mark the 7 skipped + 11 blocked `dev-improve` tasks (18, bulk) with a reason; raise `dev-improve` `max_iterations` or roll the counter before it hits 1,500.
4. Compliance mini-campaign: the 2 proposed GDPR proposals + 4 pending GDPR/erasure offers (incl. the P1 "export never downloadable").
5. Decide the 4 `proposed` campaign proposals per §2.2; leave the 4 rejected.
6. Resolve the 39 open governance reports after C4-7 removes the generator (bulk; operator-confirmed).

### C9 — Fleet safety: hub ingress/TLS and the reaper (fresh-install #14, #15, #16)
Depends on: nothing. Should land before C4-5 moves destructive lanes.
1. `HOST_LOGIN_BACKEND_PREFIXES` gains `/.well-known` (#14) — spec first; retires the `headersHelper` OAuth workaround that mints the `#N` agents. File: `server/app/services/core/ingress_config_writer.rb:73`.
2. Hub certificate issued with both DNS names as SANs, or one name standardised in knowledge (#15) — knowledge entry, not a tracked doc.
3. `AbandonedInstanceSensor`: provider `running` ⇒ approval reason; suppress the lane while the hub's own instance is silent; persistent-home guests always require approval; snapshot before terminate (#16). Spec: a replay of the 2026-10-15 fixture (fleet-wide heartbeat silence, provider `running`) produces `requires_approval: true`. File: `extensions/system/server/app/services/system/fleet/sensors/abandoned_instance_sensor.rb`.
4. Seed `system.abandoned_instance_reap` / `system.pool_guest_reap` as `require_approval` (today `auto_approve` at `monitored` on Capacity Manager).

### C10 — PR-based landing for dev-loop and campaign increments (added 2026-10-19)
Depends on: fresh-install #24 (gate green on `develop`). Complements C9.
Today increments land through `dev_merge_increment` (parked `dev.merge` approval → worker fast-forwards `develop`,
pushes every remote, audit row) — governed, but with no diff/review artifact, no CI on the exact candidate (no
workflow runs `scripts/validate.sh` or specs on `pull_request`), and no branch protection on `develop`.
1. Gate green on `develop` (#24).
2. `.gitea/workflows/validate.yml` on `pull_request` → `develop` / `release/*`: `scripts/validate.sh` (+ extension
   specs) as a required status check.
3. The driver opens **one PR per increment** (not per task) from the loop/campaign branch via the existing Gitea client
   (`server/app/services/devops/provider_client.rb`); PR body = task keys, acceptance criteria, gate results. Update the
   dev-loop / campaign skills and the Platform Developer driver.
4. `dev_merge_increment` (`server/app/services/ai/tools/dev_merge_tool.rb`, worker `Git::DevMergeIncrementJob`) requires
   PR approved + check green + head == `expected_source_sha`; merges via the Gitea API so the PR closes as merged; keeps
   the audit row (now linking the PR); GitHub mirrored after merge.
5. Gitea branch protection on `develop`, `release/*`, `master` (merge service account only; status check + 1 approval);
   restore branch-protection guardrails (`Ai::GuardrailConfig`, design doc F3).
6. Optional `dev.merge` auto-approve for `develop` only when PR approved + green; `release/*` / `master` keep the
   human-session requirement.
7. Docs + acceptance: one real increment landed end-to-end through a PR.

### Sequencing

```
C8 (triage) ──┐
C1, C2, C9 ───┼──► C3 ──► C4 ──► C7
              │     └────► C5 ──► C6 (catalog + agent docs)
C6 (1–5) can start at once; C6-6 waits for C4/C5.
```

## 8. Filed proposals

Filed 2026-10-19 14:01–14:04 UTC with `platform_campaign_propose` (9 calls; each returned `status: proposed`,
`spawned_campaign_id: null`). None was approved, started, claimed or delegated. Approve with
`platform_campaign_approve_proposal <id>`; each proposal's `configuration.plan_increments` carries the task list
from §7.

| Id | Title | Depends on |
|---|---|---|
| `01a15477-8cec-725a-8d1e-a4d544222604` | C1 Fresh install: plain-host developer path (#1–#5, #7–#13) | — |
| `01a15477-c98e-7c70-a11a-1b70020f676b` | C2 LLM provider and model resolution in core mode (#6, #18–#22) | — |
| `01a15478-30b7-7b22-9fb5-ec98fed4659c` | C3 Discovery layer: declared families, `discover_tools`, per-task grants, lane→skill | — |
| `01a15478-a63e-70df-9ed7-30bb5faa9979` | C4 Agent consolidation: 28 canonicals → 4 | C3, C2, C9 |
| `01a15478-e87a-76a1-b1c5-cd9e4442814e` | C5 MCP tool-surface reduction: 674 → ≤350 | C3-1 |
| `01a15479-2cc9-76a5-a576-e1a02cd353cd` | C6 Knowledge and docs cleanup (#17) | C4/C5 for the docs increment only |
| `01a15479-7444-794a-9220-55e415a4df74` | C7 Seed and skill pruning | C4-1, C3-4 |
| `01a15479-b693-78ac-9e32-c13286a2952c` | C8 Backlog hygiene (operator triage) | — |
| `01a15479-ebfb-73d8-b3ec-65da99b29840` | C9 Fleet safety: `/.well-known`, hub TLS SANs, reaper (#14–#16) | — |
| `01a1548d-7c63-7905-83a4-7fabe41b50cc` | C10 PR-based landing for dev-loop and campaign increments | #24 |

The 22 `[fresh-install #N]` agent proposals remain as filed; each is referenced by number from C1, C2, C6 or
C9 and none was duplicated.

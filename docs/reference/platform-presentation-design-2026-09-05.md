# Platform Presentation — Design (2026-09-05)

**Ask (operator):** "consider how best to present this information intuitively when interacting
with claude-code, platform agents and in particular the concierge… Be creative in finding
usability problems, everything should be smooth and easy to find. Duplication is bad, when it is
discovered consolidate logically."
**Scope:** what flows through the three consuming surfaces (this CLI, the platform agents, the
concierge) and how a caller finds the right verb, agent or skill. Not a new UI. Not the
front-door count or which agent each door binds to (another lane owns that). No agent is renamed
and no seed is edited here.
**Method:** every claim checked at a `file:line` (core `server/` unless prefixed
`extensions/system/`) or against a live read on the production connector. §7 lists what could
not be verified.

---

## 0. Summary

- **The concierge's wrong answer had three causes stacked, not one.** A verb and a key named as
  general facts while carrying narrow ones (`get_system_health` → `errors`); a router whose
  default exit for an unmatched question is *answer inline*; and a prompt posture that classes
  "status checks" as the inline case. Renaming the key fixed the first instance. The class is
  still open on every other surface.
- **11 misleading names found**, 2 already fixed this session, 9 open (§2). The rule that closes
  the class: **no bare fact** — a returned name carries its scope, a returned value carries its
  basis (`measured` / `inferred` / `not_measured`) and its `observed_at`. Enforced by a registry
  lint, not by review.
- **Discovery is four doors, not three** (§3): skill-graph traversal, the agent router, the
  generated CLI descriptions, and the concierge's pre-LLM router. Two are one pipeline, one is a
  cache of it, one is a second entry to the same pipeline. The survivor is the agent router
  behind `route_task`; the others become its input, its cache, and its caller.
- **10 genuine duplications** (§5), one already collapsed this session (the health surfaces).
  The largest is a hand-maintained MCP reference that is 78 actions behind the generated catalog.
- **One change first:** the no-bare-fact rule with its lint (§2.3). It is the only change that
  protects all three surfaces at once and is mechanically checkable.

---

## 1. The failure, traced

The concierge was asked how many node instances were in error and which agent owned fixing them.
It answered that none were. Twelve were (`platform_resilience failover_check` counted them,
`extensions/system/server/app/services/system/ai/skills/platform_resilience_executor.rb:414-425`).

| Link | What the code does | Where |
|---|---|---|
| Pre-LLM routing | `ConciergeService#invoke_router` calls `Ai::ConciergeRouter.route` before generation | `server/app/services/ai/concierge_service.rb:141-146` |
| Router exits | Three: `:invoked` (top skill is `one_shot` **and** auto-invokable, i.e. its executor declares exactly one required input named `intent/query/task_context/question/text`), `:delegated` (top skill is a `workflow_step`, then `AgentRouterService` picks the specialist), else `:passthrough` | `concierge_router.rb:68-92, 195-234, 112-127` |
| Why this question fell through | A fleet-status question matches a `one_shot` fleet skill whose executor takes `op:` (e.g. `system-platform-maintenance`, `system_skills_seed.rb:623-626`), so it is not auto-invokable; it is not a `workflow_step`, so it is not delegated. **Passthrough is the default exit for precisely the questions that need a specialist.** | `concierge_router.rb:199-200, 208-212` |
| Prompt posture | "Run tools DIRECTLY only for simple, single-step tasks… **status checks**, lookups, listing… or answering a question" | `concierge_service.rb:30-49` (`DELEGATION_POSTURE`) |
| Verb choice | The prompt's capability list says "Activity Monitoring: … system health"; the catalog verb is `get_system_health`; its result carried a top-level `errors` block that counts `Ai::ExecutionEvent` rows over 24 h | `server/db/seeds/ai_concierge_seed.rb` prompt; `activity_monitor_tool.rb:247-296` |
| What was fixed | The key is now `agent_execution_errors` with a comment naming this incident; the verb description now says "AI-side activity snapshot … AI AGENT EXECUTION error rates"; the composite probe reports `not_measured` rather than `ok` for anything it could not observe | `activity_monitor_tool.rb:289-296`; `extensions/system/server/app/services/system/platform/composite_health_probe.rb:1-60` |
| What was not | `get_activity_feed` still returns `errors` and `error_count` built from the same `ExecutionEvent` query (`activity_monitor_tool.rb:130-146`); the router's passthrough default; the posture text; no execution row for the turn |
| The correct route existed | `route_task` (`Ai::Tools::AgentRoutingTool`, registry `platform_api_tool_registry.rb:484`) ranks agents on six weighted dimensions with per-dimension reasons (`server/app/services/ai/routing/agent_router_service.rb:22-47`); the concierge's router already uses the same service for the `:delegated` exit (`concierge_router.rb:112-118`) — it simply never reached that exit |
| Auditability | A chat turn writes no `Ai::AgentExecution`; the writers are the tool-invoked paths (`tools/agent_as_tool_adapter.rb:93`, `tools/agent_management_tool.rb:406,475`) and `ExecutionRecorder` for Claude Code runs. `concierge_service.rb` contains no execution write | grep of `AgentExecution` across `services/ai` |

The general lesson: a confident wrong answer got through because **nothing in the returned data
said what it was a measurement of**, and **nothing in the flow required a specialist to be
asked**. §2 fixes the first, §4 the second.

---

## 2. Naming and shape of what gets returned

### 2.1 Misleading names found (a name that reads as a general fact while carrying a narrow one)

| # | Name | Reads as | Actually carries | Where | State |
|---|---|---|---|---|---|
| 1 | verb `get_system_health`, key `errors` | platform health, platform errors | AI mission counts, AI execution-event error rate | `activity_monitor_tool.rb:247-296` | key renamed `agent_execution_errors`; **verb name unchanged** |
| 2 | `get_activity_feed` keys `errors`, `error_count` | platform errors | `Ai::ExecutionEvent` rows with errors | `activity_monitor_tool.rb:130-146` | open |
| 3 | verb `system_agent_fleet_status` | the node fleet's status | one agent-fleet **mission**'s status/phase | `extensions/system/…/system_fleet_tool.rb:4141-4150` | open |
| 4 | `NodeInstance.status` in `system_list_instances` / `get_instance` | is the instance alive | provider create-time lifecycle; liveness is `last_heartbeat_at`, in a different verb (`system_get_silent_instances`). Live: `ops-cell` is `starting` with its last heartbeat 2026-08-10; `list_instances` has no status filter at all (`:1219-1222`) | `system_fleet_tool.rb:6422,6426` | open |
| 5 | `Sdwan::Peer.status` | tunnel health | recompute-lagged enum; the platform's own sensors bypass it for `last_handshake_at` ("rather than the recompute-lagged status column", `node_instance.rb:500-505`). Live: `pending` for 16 days | `sdwan_get_peer` | open |
| 6 | `Sdwan::Network.status: active` | the network carries traffic | "has at least one peer" (`peer_enroller.rb:132-136`). Live: active, zero packets ever | `sdwan_get_network` | open |
| 7 | `NodeModuleVersion.promotion_state: built`, `live_at: null` | not live | the version running on all 99 assignments; `current: true` is the truth (standing memory: the ladder is decorative) | `list_module_versions` live read | open |
| 8 | `DockerHost.status: pending`, `last_synced_at: null` | provisioning in progress | never observed; six rows from 2026-08-09 whose instances are terminated | `list_managed_docker_hosts` live read | open |
| 9 | `agent_version: "dev"` | a version | a build placeholder; the stamp fix (`efcc24fa`) is unshipped | `list_instances` live read | fix built, unshipped |
| 10 | skill/verb `sdwan_failover` | an actuator | planning-only dry run | `sdwan_failover_executor.rb:1-17` | open |
| 11 | `rails_health` in `platform_maintenance health_check` | a measurement | the literal `{ status: "ok" }` | `composite_health_probe.rb:12-20` | fixed by the probe |

Names checked and found honest: `integration_health` (counts of integration rows, scoped by
noun), `knowledge_health`, `skill_health`, `kill_switch_status`, `data_source_health`, list
`count` (documented as the total, not the page), `healthy_peers` (nullable, `null` = not
measured), `boot_lkg.arm_state`.

### 2.2 The class

Every open row is the same shape: **a lifecycle or intent state, or a narrow aggregate, is
presented under a name that a reader (human or model) resolves to the general question they
were asking.** `status` is the worst offender because it is 247 keys wide across the tool
classes and means "what the platform decided" on some rows and "what was observed" on none.

### 2.3 The rule: no bare fact

1. **Scope in the name.** A verb or key that answers a narrower question than its bare noun
   implies must carry the scope noun: `agent_execution_errors`, `agent_fleet_mission_status`,
   `provider_lifecycle_status`. A bare `errors`, `health`, `status`, `failed` at the top level of
   a read-verb result is forbidden.
2. **Basis in the shape.** Any value that a reader could take as an observation carries
   `observed_at` and a `basis` of `measured` (we asked and got an answer, including a refusal),
   `inferred` (derived from other rows, say which), or `not_measured` (could not ask). The
   composite probe's ordering (`down > degraded > not_measured > ok`,
   `composite_health_probe.rb:40-48`) is the aggregation rule; an observed-empty scope is a
   measurement, blindness is not emptiness.
3. **Lifecycle beside liveness, never instead of it.** Where a row has both a decided state and
   an observed one, the serializer returns both under distinct names
   (`lifecycle: {state, since}` and `observed: {…, observed_at, basis}`) — the instance and peer
   serializers are the first two consumers.
4. **A constant is not a measurement.** A result field whose value cannot vary is not returned
   as a status (the `rails_health` case).

**Enforcement.** A spec over `PlatformApiToolRegistry` and each tool's result builders, in the
shape of the existing `reference_counts_spec.rb` and `readme_counts_spec.rb`: it fails on any
top-level result key from a denylist of bare general nouns, and on any `status`-shaped key
without a sibling `observed_at`/`basis`. Descriptions in the registry gain the same check: a
description must name the noun the verb is scoped to. This is the one change from §0.

---

## 3. Discovery: how a caller finds the right verb, agent or skill

### 3.1 The doors that exist

| Door | Input | Ranker | Output | Where |
|---|---|---|---|---|
| A. `discover_skills` | task text | embedding-seeded traversal of the skill knowledge graph, keyword fallback | ranked **skills** with token-budgeted context | `tools/skill_tool.rb:338-350`; `skill_graph/traversal_service.rb:20-60` |
| B. `route_task` | task text (+ optional delegator, agent_type) | `AgentRouterService`: capability 0.25, trust 0.2, skill keyword overlap 0.2, policy domain 0.15, performance 0.1, cost 0.1; reasons per dimension | ranked **agents**, winner, confidence | `agent_router_service.rb:22-47`; `tools/agent_routing_tool.rb:72-93` |
| C. Generated CLI agent descriptions | the agent's policy domains, bound skills, description, pinned routing sentence; exclusion names the adjacent sibling | rendered by `Ai::ClaudeExport::RoutingDescription`; Claude Code's own model picks the `subagent_type` | 32 files in `.claude/agents/powernode/`, freshness-guarded by `scripts/check-claude-agents-fresh.sh` | `claude_export/routing_description.rb:1-40` |
| D. `ConciergeRouter` | the chat message | door A at a looser 0.85 cosine threshold, then door B for the specialist | `:invoked` / `:delegated` / `:passthrough` | `concierge_router.rb:68-92, 150-160, 112-118` |

### 3.2 Are they doors onto one thing?

Not three doors onto one thing; **two layers of one pipeline, one cache of it, and a second
caller of it**:

- A and B are sequential layers: A finds the skill, B picks the agent for it. D already composes
  them in that order ("ONE router for both sides", `concierge_router.rb:103-111`).
- C is a rendering of B's inputs (policy domains, bound skills) into a static description so a
  *different* ranker (Claude Code's model) can choose. It duplicates the ranking, not the data,
  and is kept honest by the freshness guard.
- The catalog itself (`tools/list` one-liners, `describe_tool`) is a fifth, un-ranked door: a
  caller reading 625 summaries.

### 3.3 Which survives

**Door B, widened.** `route_task` becomes the single "I have a task, who or what handles it"
entry: it runs door A internally when the caller gives only text, and returns three lanes in
one envelope — the winning **agent** (as today, with reasons), the top **skill** (with its
executor's required inputs, so a caller can see whether it is auto-invokable), and the **verbs**
that skill's executor calls (the registry already maps executor → actions for the coherence
guard). The caller gets an answer in one step and the reasons to distrust it.

- Door A stays as the skill-side primitive (missions and the router call it), not as a
  caller-facing first step.
- Door C stays, unchanged in mechanism, because Claude Code cannot call B before choosing a
  subagent; its content should be generated from B's scoring inputs (it already is) plus the
  new "verbs this agent reaches" line so the CLI reader sees reach, not prose.
- Door D stops being a separate router: its `:passthrough` exit is replaced by a B call (§4.2).
- The catalog's 625 one-liners get the scope rule from §2.3 so that a name-based pick is at
  least a truthful pick.

What this does **not** fix: five monitor-style agents with near-identical descriptions and
pairwise-identical tool allowlists (§5 row 8) will score within noise of each other on door B
and door C alike; no ranker can separate agents that differ only in adjectives.

---

## 4. The concierge answer contract

### 4.1 Three answer kinds, always labelled

Every concierge answer to a factual question carries an `answer_basis` block, rendered in the
reply and stored on the turn:

| Kind | Meaning | Must carry |
|---|---|---|
| `measured` | a tool was called and its result is quoted | verb name, `observed_at` from the result (never the turn's clock), the scope noun from §2.3 |
| `inferred` | derived from measured results by the model | the measured inputs it was derived from, and the inference in one sentence |
| `not_measured` | no verb could answer; the concierge says so | the verb it would have needed, or the specialist it delegated to |

An answer with no `answer_basis` is a bug, not a style choice. The health incident under this
contract reads: *measured: `get_system_health.agent_execution_errors` (scope: AI execution
events, 24 h)* — which does not answer "node instances in error", and the mismatch is visible.

### 4.2 Delegation as the default

The seam is `ConciergeRouter#route` (`concierge_router.rb:68-92`). Today `:passthrough` is
reached when the top skill is `one_shot` but not auto-invokable, or when no skill clears the
threshold. Change:

1. **`:passthrough` becomes `:consult`.** Before the LLM answers a question the router could not
   invoke or delegate, it calls `AgentRouterService.route(task:, delegator: concierge)` (the
   same call the `:delegated` exit makes at `:116-118`) and, when the winner's confidence
   clears a `SiteSetting` threshold and the delegation policy allows, delegates. Below the
   threshold the LLM may answer inline but the turn is labelled `inferred` or `not_measured`,
   never `measured`, unless it quotes a verb result.
2. **A fleet or platform question is never "simple".** The `DELEGATION_POSTURE` text
   (`concierge_service.rb:30-49`) lists "status checks" among inline cases; the contract
   inverts that for any question whose noun is fleet, instance, node, peer, module, image,
   certificate, volume or cluster — those go to the router first. This is a prompt/seed change
   and is **flagged, not made** (seeds are out of scope here).
3. **Ask the tool what it measures, not what it is called.** When the LLM does choose a verb
   inline, the tool bridge (`concierge_service.rb:312-360`) prepends the verb's registry
   description to the result so the model sees "AI-side activity snapshot" next to the number
   it is about to quote. The description is already the artefact the §2.3 lint keeps honest.
4. **Every turn writes an execution row.** `ConciergeService#process_message` records an
   `Ai::AgentExecution` (through `Ai::ClaudeExport::ExecutionRecorder`, already the writer for
   Claude Code runs) with the tool calls made and the `answer_basis`. The observation that "no
   agent-execution row was written for a live agent turn" is otherwise unfixable: an answer that
   leaves no row cannot be audited or scored, and `performance` is 10 % of the router's score
   (`agent_router_service.rb:46`), so an unrecorded concierge also never earns routing trust.

### 4.3 What a caller sees

- In chat: one line under the answer, e.g. *Measured by `system_list_instances` at 06:48Z
  (scope: this account's NodeInstance rows; liveness not included — see
  `system_get_silent_instances`).*
- Over MCP and in the CLI: the same block as a field on the result envelope, so a platform agent
  reading a concierge answer can refuse to build on an `inferred` one.
- When delegated: *Delegated to Fleet Autonomy (route_task confidence 0.76: policy domain
  fleet, skill match, trust 0.8)* and the specialist's answer carries its own `answer_basis`.

---

## 5. Duplication ledger

| # | Thing that exists twice | Copies | The real one, and why | Consolidation cost |
|---|---|---|---|---|
| 1 | Platform health | `platform_maintenance health_check`, `platform_resilience failover_check`, `get_system_health` | `System::Platform::CompositeHealthProbe` (this session) — the only producer that reports `not_measured` | done; the two executor ops should call the probe rather than compute their own |
| 2 | MCP action catalog | `extensions/system/docs/MCP_API_REFERENCE.md` (hand-maintained, 259 table rows, last touched 2026-09-04) vs `docs/reference/auto/mcp-tools.md` (generated; 337 actions in the reference's `system_/kubernetes_/docker_` scope) | the generated file; the reference is 78 actions behind and guarded by nothing | S: keep the reference's architecture prose (`:11`), delete its table, link the generated catalog; add it to `check-mcp-catalog-fresh.sh`'s scope |
| 3 | Smoke-seed count | "28" in `docs/SMOKE_TEST.md:8,59`, `docs/tutorials/README.md:50`, `docs/runbooks/k3s-smoke-full-lifecycle.md:361`; disk has 34 `smoke_test_*.rb` | disk | S: derive, in `reference_counts_spec.rb` (which already guards `SKILL_EXECUTORS.md`, `FLEET_SENSORS.md` and `CLAUDE.md`, `:48-380`) |
| 4 | Point-in-time counts in reports | `system-extension-evaluation-2026-09-02.md:73` (55 executors, 35 sensors), `autonomous-project-platform-gap-map-2026-09-05.md:23` (622 actions) | the generated catalogs | none: dated reports keep their numbers, but each gains an "as of `<sha>`" so a reader does not take them as current |
| 5 | Docker host listing | `system_list_managed_docker_hosts` (ext; `provisioning_state='managed'`) vs `docker_list_hosts` (core; all hosts) | one list, one filter: `docker_list_hosts(provisioning_state:)` | S: the ext verb becomes a documented alias, then retires |
| 6 | CI worker creation | `system_provision_ci_worker` (role `ci_worker`) vs `provision_ci_worker` (narrow `publish_disk_image` scope) | one verb with a `scope` parameter; both mint a `Worker` row | S |
| 7 | Federation identity | core `FederationPartner` (`federation_list_partners`, `federation_invoke_tool`; `app/models/federation_partner.rb`) vs `System::FederationPeer` (`system_sdwan_*federation*`, seven verbs); both have 0 live rows | the extension peer: it carries the state machine, the SDWAN plane and the audit log; the core partner is a cross-plane tool-invocation facet | L: one identity with two facets; an operator decision, filed not made |
| 8 | Monitor / analyst agents | `System Health Monitor`, `System Performance Monitor`, `System Analytics Intelligence`, `System Quality Assurance` (`monitoring_analytics_agents_seed.rb:30-279`), `Infrastructure Health Monitor` (`autonomy_data_seed.rb:81-85`); descriptions are adjectives ("advanced", "comprehensive"); tool allowlists pairwise identical (system-health-monitor ≡ system-performance-monitor; infrastructure-health-monitor ≡ research-analyst, by md5 of the exported allowlists) | none of them: the one with policy domains and executors is `Fleet Autonomy`; these five have read-only tools and no owned lane | M and a seed change: merge to one "Platform Observer" or retire; **not done here** (no agent renamed, no seed edited) |
| 9 | Certificate-expiry sensors | `CertExpirySensor` (ACME/Traefik certs) vs `CertificateExpirySensor` (node identity certs); different stores, deliberately (`cert_expiry_sensor.rb:5-12`) | both are real; the duplication is in the name | S: rename to `AcmeCertificateExpirySensor` / `NodeCertificateExpirySensor` (signal kinds unchanged) |
| 10 | Discovery entry | four doors (§3.1) | door B widened (§3.3) | M |
| 11 (probable) | RAG search | `query_knowledge_base` (`Ai::Tools::KnowledgeTool`) vs `search_documents` (`rag_management_tool.rb:194-201`, hybrid/vector/keyword/graph) — both "hybrid semantic + keyword search over RAG knowledge base documents" | not verified which backend each calls | S if confirmed |

Not duplicates, checked: `platform_get_agent` vs `agent_introspect` (any agent vs self);
`InstanceStatusSensor` vs `InstanceStateDriftSensor` (silent heartbeat vs DB-versus-provider
disagreement, `instance_state_drift_sensor.rb:5-8`); `cve_response` →
`cve_remediation_orchestration` → `cve_runbook_generate` (a chain); the three RAG utility
agents (distinct skills).

**The count rule.** A number restated in prose is a copy of the thing it counts. The pattern that
already works is derivation with a failing spec (`readme_counts_spec.rb`,
`reference_counts_spec.rb`, `check-mcp-catalog-fresh.sh`, `check-claude-agents-fresh.sh`,
`ASPIRATIONAL_MCP.md` "This file is DERIVED"). Rows 3 and 4 are the remaining prose counts in
the extension docs; the platform-level prose in `docs/reference/*.md` reports should carry a sha.

---

## 6. Increments

| # | Increment | Size | Ends in |
|---|---|---|---|
| P1 | No-bare-fact lint over the registry + result builders; rename the nine open names in §2.1 (keys and descriptions, not agents); `get_activity_feed` errors → `agent_execution_errors` | M | a failing spec for the next bare `errors:` |
| P2 | `lifecycle` / `observed` split on the instance and peer serializers; `basis` + `observed_at` on every status-shaped key | M | `system_get_instance` shows `starting` beside a 26-day-old heartbeat as two facts, not one |
| P3 | `route_task` widened: skill traversal internal, three lanes in one envelope, verbs reached | M | one-step discovery for the CLI and agents |
| P4 | `ConciergeRouter :passthrough → :consult`; `answer_basis` on every turn; execution row per turn | M | a fleet question is either delegated or labelled `not_measured` |
| P5 | Prompt posture change ("status checks" are not inline for fleet nouns) | S, seed | **operator decision** (seed edit) |
| P6 | Dedupe ledger rows 2, 3, 5, 6, 9, 11; sha-stamp dated reports | S each | derived counts, one docker list, one CI-worker verb |
| P7 | Ledger rows 7 and 8 (federation identity; monitor agents) | L, seed | **operator decision** |
| P8 | Generated CLI descriptions gain a "verbs reached" line from the same inputs | S | door C shows reach |

P1 before P2 (P2's keys must pass P1's lint); P3 before P4 (P4 calls it); P5 and P7 wait on the
other lane's door count.

---

## 7. What I could not verify

- The concierge's actual runtime path on the incident turn (which router exit fired). The code
  admits only the three exits in §1; no log was available read-only.
- Which backend `query_knowledge_base` calls (ledger row 11 stays "probable").
- Where the extension's `System Concierge` agent row and prompt are seeded: only the team seed
  names it (`system_operations_team_seed.rb:53`); the hierarchy seed calls it "an EXTENSION
  agent" (`ai_agent_hierarchy_seed.rb:10-15`). That is the other lane's door question.
- Whether `SiteSetting`-driven thresholds exist for the router's confidence (proposed in §4.2);
  none was found by grep.
- The exported tool allowlists were compared for four agents by md5; the other monitor pairs
  were not compared.
- Whether the frontend renders any field a §4.3 `answer_basis` block would need; the constraint
  was not to design UI, so the block is specified as data only.

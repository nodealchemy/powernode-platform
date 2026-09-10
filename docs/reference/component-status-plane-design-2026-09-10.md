# Component Status Plane — design (2026-09-10, rev 3)

**Campaign:** "Component status plane: one status model, one operator screen, one remediation
front door" (increments in §8).
**Basis:** [vision-alignment-audit-2026-09-10](../operations/vision-alignment-audit-2026-09-10.md),
two seam maps (backend, frontend), a frontend duplication inventory, and two independent
adversarial reviews of rev 1 (correctness/safety/reuse; architecture/genericity/UX). Rev 2 absorbs
all 44 review findings; the ones that changed the shape are marked **[R]**. Decisions were made
under the operator's standing grant for medium-high-confidence design decisions.

---

## 1. What this builds, in one paragraph

One **status model** every component of the platform and fleet reports into, shaped like the
Kubernetes Conditions convention (typed conditions with `status`, `reason`, `message`,
`last_transition_at`, `observed_generation`) with an Argo-style worst-child rollup; one
**operator screen** answering *what is unhealthy, why, what the platform is doing about it, and
what I must decide* on a single page, replacing five screens across two codebases; and one
**remediation front door** that routes a component's active signal to the lane that owns it,
through that lane's own gate, with its runbook attached and an evidence-first investigation that
ranks causes. The model is a keyed registry: a new component kind — core or extension — is one
`register` call carrying its own conditions, dependencies, actions and presentation, and no core
edit.

## 2. Research basis (modern practice adopted)

| Practice | Source | Adopted as |
|---|---|---|
| Typed conditions with `reason`/`message`/`lastTransitionTime`/`observedGeneration` | Kubernetes KEP-1623 | `Platform::ComponentStatus#conditions` |
| Worst-child health rollup; a resource's health from the resource alone | Argo CD resource health | verdict ladder + rollup rule (§4.1) |
| Node conditions feeding a remediation controller that acts after a condition holds | node-problem-detector, Node Readiness Controller, Cloudflare node remediation | `SignalState` + `DecisionEngine` remain the actuator; the status plane is the read model |
| One work item per problem, related resources and runbooks attached | AWS Systems Manager OpsCenter | the component drawer + the "Needs a decision" card |
| Investigation = hypotheses → evidence → ranked cause, handed to a human | Datadog Bits AI SRE | `Platform::Investigation` (§5.3) |
| Dependency graph separates root cause from downstream symptoms | OpenTelemetry service-graph practice | `dependencies` edges + upstream-most-unhealthy heuristic (§4.6) |
| Health-checked atomic updates with rollback | Sidero Omni | already present (ladder, INV-1, LKG); surfaced on the page |
| Safe automation: blast radius, budgets, canary, guardrails | StackStorm / Shoreline / PagerDuty patterns | already present (consent + disruption budgets, environment ceilings, INV-1); shown on every proposed action |

## 3. Decisions on the audit's open questions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Platform Developer gets a real actuator by a code change, not configuration** **[R]**: `TaskExecutor` attaches `GitToolExecutor`'s tools on the tool-bridge path too, so platform MCP verbs and git tools coexist; a delegated loop is created with `mission.repository`. Rev 1's "`tool_access.enabled = false`" was wrong: it never reaches git tools when an MCP server is attached, and when it does it strips the eight bootstrap verbs `BASE_GUARDRAILS` requires. | One small change at `task_executor.rb:129-141`; unlocks the worker's real test runner; keeps guidance recall and `dev_complete_task` reporting. |
| 2 | **Seed `ai.autonomy.closure_driver_enabled` (false)** and surface it with `control_plane_role_coordinator` on the operator settings page. | Off by decision, not by absence. |
| 3 | **Wire the judge and the skill-evolution last mile; delete self-challenge.** Judge runs in a worker job with an idempotency key and three explicit arms (§8 D4). `SkillVersion#activate!` writes the served prompt and A/B variants are served or not attributed (§8 D5). Self-challenge's blast radius is enumerated (§8 D6). | Self-challenge is a self-graded plain completion with a 0.5 default; no modern practice keeps it. |
| 4 | **Identity over MCP is read-only.** | Writes stay operator-only, documented as a boundary. |
| 5 | **Archive the six empty campaigns; re-vet approved offers older than a week on HEAD.** | A campaign with no lease and no tasks is a claim. |
| 6 | **`ai_skill_auto_evolution` is gated by a SiteSetting, default off** **[R]**. The cron's endpoint runs under a worker JWT with no agent principal, so an intervention-policy gate has nothing to resolve against. | Never ungated; the MCP verb keeps its own gate. |
| 7 | **Circuit-breaker consolidation is out of scope** **[R]**. `Ai::CircuitBreaker` is the model the kill switch's layer 5 opens and restores; `Monitoring::CircuitBreaker` is declared process-wide, non-tenant, with no `account_id`. Neither can absorb the other without its own campaign and an equality oracle on the halt set. | A status contributor is a read; it never licenses a model deletion. |

## 4. The status model

### 4.1 Verdicts **[R]**

`ok < held < progressing < not_measured < degraded < down`

- `held` is operator intent (cordoned, paused, drained, on hold). Rev 1 called it `suspended`,
  which already means "needs attention" in `STATUS_VARIANTS` and is a federation-peer status with
  the opposite polarity.
- `progressing` is an in-flight remediation or provisioning.
- `not_measured` is an absent measurement. It ranks below `degraded` because a missing reading is
  a gap, not a failure, but it is always rendered distinctly and never collapsed into `ok`. It
  travels under this name end to end; the `unknown` alias the platform-health REST route emits
  today is retired when `HealthPanel` is deleted (C4).
- The composite probe's ladder (`ok/not_measured/degraded/down`) keeps its relative order inside
  this one, so no existing contributor changes meaning (verified against `RANK`).

**Rollup is computed twice** **[R]**: a component is *held* when it carries a true `Held`
condition, whatever its own derived verdict; the *operational* verdict is the maximum rank over
the non-held children, and the *held count* is carried beside it. A planned drain never turns
the header amber, even while the drained node is also down; the component's own verdict still
tells the truth in the drawer. (Ruling 2026-09-10 after the A1 review: keying both halves on the
derived verdict put a cordoned-and-down node in neither bucket.)

### 4.2 Condition

```
{ type:                 "Reachable" | "Converged" | "Fresh" | "Budgeted" | "Certified" | ...
  status:               true | false | "unknown"
  reason:               "HeartbeatStale"          # CamelCase token, stable, greppable
  message:              "no heartbeat for 7m 12s" # human
  last_transition_at, observed_at, observed_generation,
  evidence: { ... }                               # the raw numbers the reason came from
}
```

`type` and `reason` are CamelCase and are never passed to a status-variant lookup (which
lowercases and would silently fall to the default variant).

### 4.3 Component status row (core, `platform_component_statuses`) **[R]**

One row per component, upserted by the sweep. Every transition writes a
`Platform::StatusEvent` row (kind `platform.component_status_changed`; `platform.component_down`
additionally on a transition to `down`) and broadcasts on `PlatformStatusChannel`
(`platform_status:<account_id>`). **One producer, always.** The system extension, when present,
mirrors transitions into its fleet feed by registering a mirror emitter from `to_prepare` — the
pull direction; core never names the extension.

| Column | Meaning |
|---|---|
| `account_id` (nullable for shared kinds, §4.4), `environment_id` (FK to `ai_environments`, nullable) | tenancy and plane |
| `component_kind`, `component_ref` | registry key and stable id; unique with account |
| `display_name`, `presentation` (jsonb: icon name, label, group_order), `links` (jsonb), `actions` (jsonb) | rendered by the page without knowing the kind |
| `verdict` | §4.1 |
| `conditions`, `dependencies` (jsonb) | §4.2; `[{kind, ref, relation: requires\|serves\|hosts\|backs\|routes}]` |
| `remediation` (jsonb) | `{state, signal_kind, fingerprint, approval_request_id, last_outcome, stuck, runbook}` |
| `observed_at`, `observed_generation`, `last_seen_sweep_at`, `last_notified_at` | freshness, reap, escalation claim |

`remediation.state ∈ none | auto_in_progress | awaiting_operator | stuck | remediated | not_actuatable`,
derived from `SignalState`, `RemediationOutcome`, `ApprovalRequest` and the lane binding — never
hand-written.

Migration conventions the A1 migration follows: `id: :uuid, default: -> { "uuidv7()" }`;
`t.references` with `type: :uuid` and no separate `add_index`; `t.references :environment,
foreign_key: { to_table: :ai_environments, on_delete: :nullify }`; a named composite index only
where the generated name exceeds 63 characters; JSON defaults on the **model** as lambdas;
`# frozen_string_literal: true`; `schema.rb` regenerated in core mode only.

### 4.4 Registry (generic seam) **[R]**

`Platform::Status::Registry.register(kind, contributor)`. A contributor answers:

| Method | Purpose |
|---|---|
| `each_component(account) { record }` | enumeration, **within the contributor's own scope** — terminated, archived and soft-deleted records are excluded by the contributor, and the doc for each kind states its scope |
| `account_scoped?` | default `true`; `false` for process-wide kinds, whose rows carry a null account, render in a "shared infrastructure" section, and never enter a per-account rollup |
| `ref_for`, `display_name_for`, `links_for` | identity and navigation |
| `presentation` | `{icon: "<Lucide icon name>", label:, group_order:}` — the same string-icon convention `FeatureSettingsTab` already uses, so no extension imports core icon components |
| `conditions_for(record)` | the only place kind-specific logic lives |
| `dependencies_for(record)` | reuses `BlastRadiusService` buckets, `ModuleDependency`, `Sdwan::ServiceBackend`, instance→node, peer→network |
| `actions_for(record)` | `[{key, label, method, path, permission, destructive, confirm: {prompt, requires_reason}}]` — the page renders buttons from data and issues the request; core learns nothing about the kind |
| `signal_resolver` | maps a `FleetEvent`/`SignalState` to this component (by `node_instance_id`, `payload.instance_id`, `certificate_id`, ...) |
| `runbook_key`, `owner_agent_slug` (optional) | drawer and investigation defaults |

The drawer resolves an optional rich panel by a **derived** slot id,
`platform.status.drawer.<component_kind>`, through the existing `registerComponentSlots` seam
(global ids, one component per id, last write wins — documented as a hazard). The page subscribes
to `featureRegistry.getVersion()` so a runtime extension that registers after first render is
picked up (the `CostPage` precedent).

Core registers: `ai_provider`, `integration_instance`, `docker_host`, `kubernetes_cluster`,
`agent_circuit_breaker` (over `Ai::CircuitBreaker`), `provider_circuit_breaker` (over
`Ai::ProviderCircuitBreakerService.all_provider_stats`). The system extension registers from its
engine's `to_prepare` with **one line** — `System::Status::Contributors.register_all!` — which
globs `app/services/system/status/contributors/*.rb`, so B-lanes add files and never share one:
`platform_subsystem` (13, over `PlatformHealthSnapshot`), `node_instance`, `node`,
`instance_pool`, `node_module` (drift), `sdwan_peer`, `sdwan_service`, `storage_assignment`,
`acme_certificate`, `federation_peer`. The eight per-model status enums are **not** replaced;
each contributor normalizes its own enum into conditions.

`Monitoring::UnifiedService#calculate_health_score`, `Ai::MonitoringHealthService#calculate_overall_health_score`
/ `#determine_health_status` and `AiMonitoringConcern#determine_health_status` are declared
non-authoritative by this design and are deleted in E7/E7b (no-legacy rule); the rollup is the
one health score. `Monitoring::AlertingService` is **not** a rival producer (rev 3 correction: it
produces no verdict, it delivers to Slack/email/webhook channels); it stays and becomes the
channel-delivery seam `Escalation#notify` also calls (E8), with its channel configuration moved
from ENV to SiteSettings.

### 4.5 Sweep **[R]**

Three artefacts, because the server runs no Sidekiq: a `worker/` job (`PlatformStatusSweepJob`,
cron every 60 s, Redis lock `platform:status:sweep:lock` TTL 240 s — overlap by design), a core
`worker_api/platform/status_sweep` route and controller, and `Platform::Status::SweepService`.
`SweepService.run_once!(account)` is callable without the cron, so A1's oracle is executable
before A2 lands. Guards: kill switch (`KillSwitchGuard` semantics) and the dual-plane standby
fence. It reads state that sensors already maintain; it does not probe. A contributor that raises
marks its components `not_measured` with `reason: ContributorError` — the composite probe's
oracle rule, applied everywhere.

**Reap arm:** a row whose `last_seen_sweep_at` is older than 3 sweeps is deleted, so a component
whose record is gone does not keep a verdict. Oracle: terminate an instance, run two sweeps,
assert zero rows.

**Budget:** one batched query per contributor per account; `impact()` walks a preloaded edge set
(`.includes`), never per-node lookups. Stated ceiling: 150 components × 16 kinds per 60 s sweep
on the reference fleet.

**Staleness honesty:** the `platform_subsystem` kind carries the snapshot's `captured_at` as
`observed_at` and a `Fresh` condition that goes false past
`system.platform_health_check_interval_minutes` × 2 with `reason: SnapshotStale`. An account with
no snapshot (the attribution clone is absent) produces a `not_measured/NoSnapshot` row, never
nothing.

### 4.6 Rollup, impact, environment

- `rollup(scope)` → operational verdict + held count (§4.1) over account, environment, kind, or
  a component's downstream closure.
- `impact(component)` → dependents' count and worst verdict, reverse-walked to depth 4,
  cycle-safe (the `NodeModule#all_dependencies` visited-set shape), from one preloaded set.
- `root_cause_candidates(component)` → within the unhealthy connected subgraph, the
  upstream-most unhealthy components ranked by (out-degree of unhealthy dependents, earliest
  `last_transition_at`). Labelled as a heuristic on the page.
- **Environment filter is three-valued** **[R]**: in-plane, plane-less, out-of-plane. Most core
  kinds and `platform_subsystem` carry no environment; filtering to a plane keeps plane-less
  components visible under an explicit label and never shows another plane's instances. Both
  arms asserted.

## 5. Intelligent remediation

### 5.1 Front door **[R]**

`Platform::RemediationRouter.route(component, signal_kind)` resolves through
`Platform::Remediation::Registry` (keyed by `signal_kind`) to one registered lane and returns
what that lane reports: the resolved intervention policy, consent and disruption budget headroom,
environment ceiling, blast radius, runbook, and whether the lane can proceed.

**Core never constructs a proceed.** A lane registered by the system extension proceeds only by
calling `System::Fleet::FleetAutonomyService#gate_action!` — the same entry the tick uses, which
applies the routed-lane refusal, the consent budget and the INV-1 self-management fence that
`Ai::AutonomyGate` does not. A lane registered by core for AI-provider health calls
`Ai::SelfHealing::RemediationDispatcher`. A signal with no lane is `not_actuatable` with the
reason rendered. **Every `platform_subsystem` recommendation is `not_actuatable` by default**;
the only actuation path for the control plane's own components is an extension lane that runs
the fence. Oracles: a lane whose consent budget is exhausted returns `pending`; a recommendation
naming the self-hosting instance renders `not_actuatable` with the INV-1 reason and one naming
any other instance does not; `ConsentBudgetService` shows one consumption per proceed and zero per
advisory.

Core's own write is `request_approval` (declared `mutating: true`, action category `approval`,
seeded policy row, never in `BootstrapVerbs`). **There is no `respond_to_approval` verb** **[R]**:
the fleet gate mints those approvals to reach a person, and an agent that can answer them has
closed the loop on itself. Responding stays operator-side (REST and the page).

### 5.2 Runbooks **[R]**

`Platform::Runbook::Registry` (core, keyed by `signal_kind`) → `{doc: "<path>#<anchor>"}` or
`{generator: <executor>, args:}`. The system extension **creates**
`extensions/system/config/runbooks.yml` (it does not exist today) covering all 53 bound signal
kinds from the 26 hand-authored runbooks, each entry a doc anchor or an explicit
`not_documented: true` with a reason. The both-arms spec (every bound kind has an entry; every
entry names a bound kind) **lives in the extension**, because it reads `SIGNAL_BINDINGS`. A5
(registry) lands before B4 (YAML). Runbook coverage is a spec-only assertion; it is not routed
through `GovernanceGapSensor` (rev 1's B5 is dropped — a missing doc is not a policy-ownership
gap).

### 5.3 Investigation **[R]**

`Platform::Investigation` (table): `component_kind`, `component_ref`, `trigger`
(operator | stuck | down), `status`, `evidence` (jsonb), `hypotheses`
(`[{cause, evidence_refs, confidence, recommended_action_category, runbook}]`), `conclusion`,
`agent_id`, cost, and a `fingerprint` unique among open rows (one open investigation per
component, the `AgentObservation` dedupe shape).

`Platform::InvestigationService` **extends `Ai::SelfHealing::CrossSystemCorrelator`** as its
evidence assembler (it already assembles failures, matches them temporally and causally, and
returns ranked `suggested_cause` with confidence) with: conditions at start, the dependency chain
with verdicts, `FleetEvent`s by correlation in the window, recent module changes and promotions,
`RemediationOutcome` history, and matching learnings. It then invokes the owning canonical agent
(`owner_agent_slug`, default the Infrastructure Generalist) through the existing gated skill path
to rank hypotheses, **in a worker job**, never a request thread.

Confidence rule, stated so it can fail: share of supporting evidence, **discounted by candidate
count and by the number of independent evidence classes**, with a ceiling for a single candidate
supported by a single class; `not_measured` is distinct from `0.0` and is returned when the
evidence set is empty. Both arms: one candidate from one class does not return 1.0; two
candidates split proportionally. The same rule replaces `attribute_failure`'s current
share-of-total (which already returns 1.0 for a single candidate by construction).

Triggers: the operator's "Investigate" button; automatically on `fleet.remediation_stuck` and on a
`platform_subsystem` transition to `down`, bounded by the open-fingerprint rule and a per-account
daily cap SiteSetting. A completed investigation records a learning through the existing
extractor seam and, when its recommended action is a bound lane, offers it through §5.1 under
that lane's gate.

### 5.4 Escalation that reaches a person **[R]**

A `platform_subsystem` transition to `down` creates a `Notification` (critical) and a
`platform.component_down` event; `degraded` for longer than SiteSetting
`platform.status.degraded_notify_after_minutes` (default 15) creates one at warning. Rate limiting
uses the row's own `last_notified_at` and a SiteSetting interval — a core claim, since
`SignalState.claim_notification!` is extension-side and keyed by fleet fingerprint. Fleet kinds
keep their lane's escalation; A7 covers core kinds and `platform_subsystem`. The choice is the
contributor's, not core's: the contract carries `escalates?` (default true) and every fleet
contributor answers false, so core never names a fleet kind (ruling after the A7 review).

## 6. Operator screen **[R]**

Core page `/app/status` ("Status") in `frontend/src/features/platform/status/`, reading
`GET /api/v1/platform/component_statuses` (index, show, rollup, impact) under permission
`platform.status.read` (granted to admin, owner, manager, member — a status page only admins can
open does not replace five pages a member could reach), subscribing to `PlatformStatusChannel`
through `usePageWebSocket`, with a 30 s poll as a genuine fallback.

Layout: header with the operational rollup, held count, environment (three-valued) and kind
filters; a grid of component cards grouped by `presentation.group_order` using a new core
`VerdictBadge` (closed six-verdict union, coverage asserted in a plain `.ts`, never a `.test.ts`);
a right rail with three lists (Needs a decision, In progress, Stuck); a drawer per component with
tabs Conditions, Dependencies (upstream and impact), Events (the component's status events; "Signals" in rev 2), Remediation, Runbook,
Investigations, plus the derived slot for a kind's rich panel. **No new kill-switch banner**:
`DashboardLayout` already mounts one app-wide; the duplicate mount on the Autonomy page is deleted.
Every number carries its basis.

`StatusBadge` **stays in the extension** (its coverage file imports eight extension types, and
its header documents why core must not depend on that vocabulary); it gains entries for `held`,
`progressing` and `not_measured` with deliberate variants (`not_measured` is never the default
grey), and maps the six verdicts into its own table.

Absorbed and deleted, gated by the **41-row capability checklist** in the architecture review
(session-local; copied into the C4 task brief): `HealthPanel` (Compute), the fleet tiles, signals
feed and attribution modals (Operations → Fleet; the honeypot tile's severity ratchet and the
boot-replay permission refusal are carried, not dropped), `SelfHealingDashboard` and its timeline
and correlation views (Observability; the feature-flag-disabled banner is carried as an honest
`not_actuatable` state), and `ApprovalQueuePanel` (Autonomy; its `OneShotRevealModal` queue is
security-relevant and is carried). Two capabilities the absorbed surfaces never had are sized as
new work: approval-chain step display and live updates on the queue. Bulk approve stays
unsupported. The `ai.monitoring.read` permission typo in the self-healing controller dies with it.

## 7. What this campaign also carries

- clock: scheduled discovery cron, the Platform Developer actuator, the closure-driver setting
- self-judgement: judge, skill-evolution last mile, self-challenge deletion, gated auto-evolution
- honesty: annotations from `declared_actions`, `integration_health` probe fix,
  `platform_resilience` rescue removal, `get_sensor_config` listing all DB-tunable sensors,
  `query_learnings` keyword fallback
- reach: read-only identity/audit/provider/schedule/webhook verbs; `request_approval`
- hygiene: model-id lint, HIER-P0, `BASE_GUARDRAILS` gate line, docs counts, campaign archive,
  rival health-score deletion
- frontend consolidation: the 20-item duplication inventory, each with an importer-count and
  capability oracle

## 8. Increments

Each ends in an actuator or an operator, never a returned plan; each names its oracle. Lanes are
by repo and by file partition so no two in-flight increments co-edit a file. One MCP tool class
per increment. Sequencing constraints are stated where they exist.

### Track A — status model (core)

| # | Increment | Oracle |
|---|---|---|
| A1 | `Platform::ComponentStatus` migration + model + `Platform::Status::Registry` + contributor contract + `SweepService.run_once!(account)` + reap arm | a fake kind registered → rows after `run_once!`; unregistered → reaped after 3 runs; a raising contributor → `not_measured/ContributorError` |
| A2 | `PlatformStatusSweepJob` (worker, 60 s, Redis lock) + `worker_api/platform/status_sweep` + guards + `Platform::StatusEvent` + `PlatformStatusChannel` + the one-time `usePageWebSocket` map entry | a transition produces exactly one event row and one broadcast; kill switch halted → no-op with reason |
| A3 | Core contributors: `ai_provider`, `integration_instance` (read-only), `docker_host`, `kubernetes_cluster`, `agent_circuit_breaker`, `provider_circuit_breaker` | every enum value of each source maps to a condition; no `account_id` fabricated |
| A4 | `platform.status.read` permission (`define(namespace: "platform")`), REST index/show/rollup/impact (query logic in services, serialization in a concern, controller under 300 lines), `PlatformStatusTool` with `platform_list_component_status`, `platform_get_component_status`, `platform_component_impact` (declared, annotated), wire name `not_measured` | member role can read; three-valued environment filter both arms; annotations emitted from declarations |
| A5 | `Platform::Remediation::Registry` + `RemediationRouter` + `not_actuatable` + `Platform::Runbook::Registry` + `PlatformRemediationTool` with `request_approval` (declared, gated, not bootstrap) | INV-1 both arms; consent-exhausted → pending; unrouted kind → `not_actuatable` with reason |
| A6 | `Platform::Investigation` + service over `CrossSystemCorrelator` + worker job + `PlatformInvestigationTool` + learning write; `attribute_failure` confidence rule replaced | confidence both arms; one open per component; empty evidence → `not_measured` |
| A7 | Core escalation (`down`/`degraded` notifications, `last_notified_at` claim); `platform_resilience` rescue-to-all-clear removed | a `down` transition yields one notification per interval; an exception in resilience renders `not_measured`, never "no stress" |
| A8 | `integration_health` probe fix: worker sweep gets an internal route it may call; `health_status`, `consecutive_failures`, `last_health_check_at` persisted from the existing derivation; auto-pause reachable. Sequenced after the peer session releases `devops/registry_service.rb` | a failing integration reaches `unhealthy` and pauses after three failures; the verb can report a non-`unknown` bucket |

### Track B — extension contributors and lanes (extension)

| # | Increment | Oracle |
|---|---|---|
| B1 | `System::Status::Contributors.register_all!` (glob) + the one engine line + `platform_subsystem` contributor with `Fresh`/`NoSnapshot` | clone-less account → `not_measured/NoSnapshot`; stale snapshot → `Fresh=false/SnapshotStale` |
| B2 | `node_instance`, `node`, `instance_pool` contributors with `BlastRadiusService` edges and `actions_for` (cordon, uncordon, reboot, replace with permissions and reason prompts) | terminated instances excluded; actions carry the permission the REST door checks |
| B3 | `node_module`, `sdwan_peer`, `sdwan_service`, `storage_assignment`, `acme_certificate`, `federation_peer` contributors | each enum value maps to a condition |
| B4 | Fleet lanes registered into the remediation registry (proceed via `gate_action!`); mirror emitter into `FleetEvent`; `runbooks.yml` for all 53 kinds + the extension-side both-arms spec; `get_sensor_config` lists every ladder-tunable sensor (derived; eight today). Sequenced after A5 | a lane proceed consumes one consent unit; every bound kind has a runbook entry or a reasoned `not_documented` |

### Track C — operator screen and frontend consolidation (frontend)

| # | Increment | Oracle |
|---|---|---|
| C1 | Core `VerdictBadge` + verdict coverage `.ts`; extension `StatusBadge` gains `held`/`progressing`/`not_measured` | `tsc` fails if a verdict is unmapped; `not_measured` is not `secondary` |
| C2 | `/app/status` page: grid, rail, filters, live channel, poll fallback, registry-version subscription; delete the duplicate kill-switch banner on the Autonomy page | page renders a kind that registers after first render |
| C3 | Drawer tabs + derived slot resolution + `actions_for` buttons with `useReasonConfirm`-style confirmation | an action's button is hidden without its permission and prompts for a reason when declared |
| C3b | Approval-chain step display and live queue updates (new capabilities the absorbed panel never had); `ApprovalRequest` TS type gains `current_step`/`step_statuses`/`approval_chain_id` | a two-step chain renders both steps; a new approval appears without reload |
| C4 | Absorb and delete `HealthPanel`, fleet tiles, `SelfHealingDashboard` family, `ApprovalQueuePanel`; redirects; 41-row checklist named in the deletion commit | every checklist row green before its source is deleted |
| C5 | `ui/TabContainer` → `layout/TabContainer` (6 callers), delete `TabNavigation`, `TabButton` | zero references to the deleted paths |
| C6 | Delete dead forms/atoms/utils (18 files: `EmailField`, `PasswordField`, `MarkdownEditor`, `CheckboxField`, `ErrorMessage`, `ViewToggle`, `SuccessAlert`, `apiUtils`, `mcpClient`, `nodeColorUtils`, `resilienceUtils`, `debounce`, `statusHelpers`, `themeUtils`, `retryUtils`, `AIMonitoringPage` shim + barrel, `ProviderHealthDashboard`, dead `SelfHealingDashboard` export) | each basename has zero importers; no dynamic import |
| C7 | Formatters: migrate 13 `formatDuration`, 10 `timeAgo`, 2 `formatBytes` onto `shared/utils/formatters.ts` after per-site unit/format diff | zero local definitions outside `formatters.ts`; snapshot tests unchanged |
| C8 | `usePolling(fn, ms)` hook; migrate the 34 `setInterval` sites starting with the two near-identical pairs; migrate the 5 raw `wsManager.subscribe` sites onto a hook | zero raw `setInterval` in components; zero raw `wsManager.subscribe` outside hooks |
| C9 | ~~Delete the unwired Playwright setup~~ — SKIPPED (rev 3): the smoke specs carry cross-browser coverage (chromium/firefox/webkit) Cypress lacks; CI wiring filed as an offer instead | `npm ls @playwright/test` errors; no `playwright` dir |
| C10 | Merge `FederationHubPage` into `ServiceDeliveryPage`; relocate its eight non-federation panels to `ComputePage`; redirects | the eight panels each keep ≥1 importer |
| C11 | Delete the legacy redirect routes (17 measured, not the 15 the audit estimated) in `DashboardPage.tsx` (no-legacy rule; the operator confirmed no external bookmarks are a concern by granting the rule) | no `<Navigate>` to a renamed path remains |
| C12 | Split `InstancePoolsPage`, `NodeDetailModal`, `ProviderDetailModal`, `ProviderFormModal`, `CreateInstanceModal` onto `PathTabs`/section components | existing tests green with no assertion changes |
| C13 | Diff-then-decide pairs: `RalphLoopListPanel` vs `RalphLoopList`; `DashboardAIOverview` vs `MonitoringOverviewCards`; the six feature websocket hooks vs `usePageWebSocket`; core `maintenanceApi` vs extension `platformHealthApi` | a written diff per pair, then merge or a recorded keep-both reason |
| C14 | Shared `Modal` primitive with nested dialogs: unique title ids per instance (aria-labelledby announces the right dialog), Escape handled by the topmost dialog only, body scroll lock refcounted (C3 review F5–F7) | a nested-dialog test per behaviour |
| C15 | Nav-link reachability lint: every `/app…` href/`navigate` literal in `frontend/src` and the extension frontends resolves to a routed path; equality ratchet driven to zero (54 unreachable found at review, 52 pre-existing); the four surviving legacy redirects in `AdminSettingsPage.tsx`/`App.tsx` deleted (C11b) | lint green with an empty baseline |

### Track D — loop closure (core)

| # | Increment | Oracle |
|---|---|---|
| D1 | Discovery cron (weekly, per account, kill-switch and environment gated) running the lint analyzer and filing pending offers through `create_improvement`; bounded by the environment-tier ceiling and pending-only offers, deliberately NO enable flag (unlike `ClosureDriverService`, which spends LLM calls) | a seeded lint violation → exactly one offer after one tick, zero after two |
| D1b | Run discovery where the linter exists: lease a CI runner (`lease_ci_runner`) with the repository's own bundle, run the analyzers there, ingest diagnostics through the same filing path; the Rails process never executes a repository's Gemfile | a deployed node with no dev bundle files an offer for a seeded lint violation |
| D2 | Git tools attached on the tool-bridge path in `TaskExecutor`; `campaign_delegate` creates the loop with `mission.repository`; bridge result no longer hardcodes `checks_passed: true` | a delegated task ends in a commit SHA **read back from the repository** and a `TestVerificationService` verdict of `verified`; a task the agent cannot implement yields no SHA |
| D3 | Seed `ai.autonomy.closure_driver_enabled` (false) and expose it with `control_plane_role_coordinator` on settings | the driver runs only when the row is true |
| D4 | Judge: worker job (no request thread), idempotency key `(execution_id, task_id)`, three arms (SiteSetting `ai.evaluation.enabled` off → `not_measured` (rev 3: the Flipper flag is deleted — no operator surface could reach it); a judge reply missing or mis-typing any dimension → `not_measured`, never a clamped score; no evaluable execution → `not_measured` with reason; evaluated → row), wired from `dev_complete_task`, writes trust `quality` and `SkillVersion#record_outcome!`; parser/prompt schema aligned; Claude Code callers evaluate against the `record_agent_execution` row when present | a retried completion writes one evaluation; all three arms asserted |
| D5 | `dev_complete_task` gains a declared execution-id parameter (the attribution-key producer D4 reads); `ai.evaluation.enabled` default true with `ai.evaluation.daily_cap` (20), both on the Autonomy tab; `SkillVersion#activate!` writes `ai_skills.system_prompt`; `SkillMutationService` routes through `start_ab_test` (the clamp bypass is the defect); variant prompt served by the same routing that attributes outcomes, or attribution removed | after `activate_version`, `build_skill_system_prompts` returns the new text; an outcome recorded during an A/B lands on the version actually served |
| D6 | Delete self-challenge: 3 verbs, service, 2 jobs, internal controller, enqueue, `tool_relevance_filter` regex, `Account has_many`, `challenge_derived` strategy, frontend intelligence surface; keep `self_challenge` in `TRAJECTORY_TYPES` for historical rows; `ai_skill_auto_evolution` behind SiteSetting `ai.skill_auto_evolution_enabled` (default false) | zero references outside the trajectory enum; the cron no-ops with a logged reason when the setting is false |
| D7 | `query_learnings` keyword fallback on an empty semantic result; embedding backfill rake for learnings | `query_learnings(query: "fabricated review")` returns the correction learnings |

### Track E — reach and hygiene (core)

| # | Increment | Oracle |
|---|---|---|
| E1 | `IdentityReadTool` (list/get users, roles, permissions, audit logs), `ProviderReadTool` (LLM providers, models), `ScheduleReadTool`, `WebhookReadTool` — all declared read-only; `mcp-and-tools.md` states the identity boundary. Sequenced after A4 on `permissions.rb` | each verb is refused without its read permission |
| E2 | Annotations exported from `declared_actions`; docs catalog filtered through `advertised_action?` | 3 mutating `perceive/measure` verbs lose `readOnlyHint`; 72 destructive verbs gain `destructiveHint` |
| E3 | Model-id lint (`spec/lint/`) with catalog-path allowlist over `server/`, `worker/`, `extensions/`; the 12 Class-A fallbacks and `devops_integration.rb:11` fixed | lint red on a seeded `\|\| "claude-x"`; green on the catalog files |
| E3b | Provider defaults come from the synced catalog: `Configurable#set_default_configuration_from_type` stops writing literal model lists and `default_model` (openai/anthropic); a data migration clears only literal defaults absent from the synced catalog (count stated, >5 needs the operator); the lint sees `%w[]` arrays and hyphenless ids; the Ollama `|| "llama2"` fallback is deleted | an openai provider with an empty catalog refuses `no_model_configured`; with a synced catalog it resolves a model in that catalog |
| E4 | HIER-P0 (empty `allowed_delegate_types` means none); `BASE_GUARDRAILS` verification-gate line; `bootstrap_verbs_spec` derivation updated | a leaf with an empty list cannot delegate |
| E5 | Docs counts regenerated under the drift guard; stale unit names removed; "self-improving" qualified until D-track lands | drift guard green |
| E6 | Archive the six empty campaigns; re-vet approved offers older than a week (promote or dismiss with reason) | zero active campaigns with no tasks |
| E7 | Delete `Monitoring::UnifiedService#calculate_health_score` as a rival producer, migrating its callers (`overview`, `dashboard`, `broadcast_metrics`) onto the rollup; lint guard with a red-arm fixture | zero references; `health_score` absent from the wire |
| E7b | Delete `Ai::MonitoringHealthService#calculate_overall_health_score`/`#determine_health_status` and `AiMonitoringConcern#determine_health_status`; the `health` action and `get_system_overview` carry rollup rows for the database/redis/providers/workers kinds | both literals in the lint guard, one red arm each |
| E8 | `Escalation#notify` fans out through `Monitoring::AlertingService` channels beside the in-app Notification; channel config off ENV: the three credentials (Slack webhook URL, alert webhook URL, webhook token) in `Security::SecretStore` (platform-global, audited, write-only on the wire — `configured: true|false`, never via MCP); `email` and three `min_severity_*` as SiteSettings seeded `is_public: false`; `ALERTING_ENABLED` and `SLACK_ALERT_CHANNEL` deleted (a channel is live iff configured); the two event callers keep the service; channels fire independent of the in-app recipient list (shared rows and account rows, row coordinates only, one claim per row); the plain settings are absence-means-off (no seeded rows; the operator surface creates them on first write); per-account channels are future work | a degraded transition with a configured Slack channel produces one delivery, rate-limited by `last_notified_at` |

## 9. Non-goals

- No new sensor family. The status plane reads what sensors maintain. (A8 fixes an existing
  sensor's persistence; it adds none.)
- No second producer of platform-subsystem health; the composite probe stays the one.
- No change to gate semantics: the page and the router show and route; the lane's gate decides.
- No circuit-breaker consolidation (decision 7).
- Workload (application) sensing stays with the fleet-knowledge campaign.

# Autonomous Project Platform — vision, live smoke, gap map (2026-09-05)

**Operator ask (2026-09-05).** Interpret the system extension's scope and vision; design tight MCP
integration where platform agents regularly check every component's health, perform pending and
scheduled work, and start and then keep managing platform-deployed projects — each project with its
own template, modules, agents and skills. Find what is missing for a "magically autonomous"
development/deployment environment, find usability problems and duplication, and shape the work as
dev-improve tasks and/or a campaign. **Report only — nothing was implemented** (another session is
draining dev-loop).

Builds on, and does not repeat: `autonomous-infrastructure-readiness-2026-08-12.md` (§7 do-not-automate
list still governs), `autonomous-project-operations-gap-map-2026-09-02.md` (APO campaign `01a0609d`,
25/25 increments on the branch: replace/reap instance, promote replica, restore volume, snapshot policy),
`system-agent-hierarchy-proposal-2026-09-03.md` (campaign `01a06878`, 14/14 on the branch).

---

## 1. What the extension IS (scope + vision, as read)

The system extension is the substrate: PXE/UKI boot → signed module supply chain → SDWAN fabric → fleet
autonomy. Its vision, stated three times by the operator (07-17, 07-28, 09-02), is an agent that turns
intent into a running, networked, stored, exposed, monitored and self-repairing workload, and keeps
improving how it does that. The verbs exist (65 skill executors, 36 sensors, 622 MCP actions). What is
missing is not verbs; it is **the nouns and the clock**:

- **No noun for "project."** `System::ProjectMetric belongs_to :mission`; a "project" today is an
  `Ai::Mission` of type infrastructure. There is no record that binds template + module set + instances +
  SDWAN network + volumes + exposed services + repo + budget/bounds + SLOs + the agent team that owns it.
  Missions end; projects do not.
- **No clock for agents.** Every scheduled thing is a deterministic cron (10 extension entries, ~25 core).
  No mechanism runs an *agent* on a cadence. `Ai::Autonomy::GoalDrivenSchedulerService#should_execute_now?`
  exists but its only caller is `ralph_loop_closure_service.rb`; nothing ticks agent goals
  (`server/app/services/ai/autonomy/goal_driven_scheduler_service.rb`, grep across `worker/app` and
  `server/app` for `GoalDrivenSchedulerService`: 1 caller).
- **No single health truth.** Three partial health verbs disagree (§2).

## 2. Live smoke on ops-hub (instance principal, read-only verbs, 04:48 UTC)

Run through the `powernode` connector (dev-cell instance principal). The admin-user REST path was not
exercised: no admin bearer token is available on this cell and `powernode-local` (dev Rails) is down.

| Probe | Result | Reading |
|---|---|---|
| `system_platform_maintenance op=health_check` | `overall: ok` — rails, postgres, acme(0), federation(0) | Only 4 subsystems. The executor's own comment (`platform_maintenance_executor.rb:24-25`) promises worker, redis, sdwan too; `health_check` at `:258-263` builds only four. |
| `system_platform_resilience op=failover_check` | **11 NodeInstances in `error`** — 9 `ci-native-builders` ephemeral pool members (08-09 → 09-04), `powernode-ops-cell-1/2` (since 08-09) | The health check above said OK. Same platform, same minute. |
| `system_recent_signals` (40 events ≈ 46 s) | `fleet.tick_complete`: **25 signals → 25 decisions → 25 `deduped`, 0 executed**. 12 `system.config_drift` (assignments changed 07-19 … 08-10, `last_apply_at: null`), `system.boot_image_drift` on dev-cell and ops-hub, `system.sdwan_hub_unreachable` **critical** on `dryrun-fabric` (0 peers, a test network) | Every minute the loop re-detects the same standing state, writes a `decision.deduped` FleetEvent per signal (`learning_extractor.rb:47` already calls these "zero-information buckets, 29k/day"), and acts on none. Nothing ages, escalates, or reaches a person. |
| `system_list_instances` | 98 rows; the first 50 are all `ci-native-builders-*`, 48 of them `terminated` | No `status` filter on the verb (`system_fleet_tool.rb:1218`); an operator or agent cannot ask "what is running." |
| `system_list_templates` / pools / services | 12 templates, 1 pool (healthy, 1 ready), **0 `Sdwan::Service`** | Nothing is exposed; the service-delivery plane has no live consumer. |
| `get_sensor_config` | 4 configurable sensors of 36 | Thresholds for the other 32 are constants. |
| `discover_skills` ("check health of every component, run scheduled tasks, manage projects") | Platform Maintenance 0.64, Platform Resilience 0.54, Activity Monitoring 0.51, DevOps Engineer 0.48 | Four skills answer the same question; the DevOps Engineer prompt still names `powernode-backend@` units that CLAUDE.md says do not exist. |

**Deploy lag (corrected 05:10 UTC by content on the node):** ops-hub runs core `9d2185b9e`
(= `develop`, built 2026-09-04 16:17) and the extension at `96b9463a` (remote `develop`;
`hierarchy_reconciler.rb` is present on the node). What is undeployed is the drain since then:
25 core commits (`develop..dev-loop/dev-improve`) and 25 extension commits (`96b9463a..HEAD`),
i.e. the 09-04/09-05 dev-improve fixes, not the hierarchy campaign. An earlier draft of this
section said "24 core / 409 extension" — the 409 was measured against a stale LOCAL `develop`.

## 3. Gap map — what a magically autonomous environment still lacks

Ordered by leverage. Each names the seam it extends (reuse-first).

| # | Gap | Evidence | Seam to extend |
|---|---|---|---|
| G1 | **Composite platform health** — one producer, persisted, covering rails, worker-web (`:4567/health`), sidekiq, redis, postgres, traefik, MCP endpoint, tick-loop liveness, provider egress reachability, fleet error/silent counts | §2 rows 1-2; `activity_monitor_tool.rb:236` (`get_system_health`: missions/agents/providers only); memory `ops-hub-egress-default-deny-blocks-ai-providers` (a provider timeout reads as a credential problem) | `PlatformMaintenanceExecutor#health_check` + `PlatformHealthController` it "mirrors"; persist as a `System::FleetEvent` kind or a `PlatformHealthSnapshot`; one MCP verb; other three become aliases |
| G2 | **Standing-signal hygiene** — age, escalation, and an inbox | §2 row 3; `notify_and_proceed` ends in a FleetEvent + `Rails.logger` (`decision_engine.rb:292-296`) | `DecisionEngine` dedupe path (`:1039`): suppress per-tick `deduped` events, keep a `first_seen/last_seen/tick_count` on the fingerprint; a signal standing > N ticks with no remediation → `Notification` + approval-inbox card; `InstanceUnrecoverableSensor` + `reap_instance` for errored **ephemeral** pool members |
| G3 | **Agent duty schedules** — run an agent (not a job) on a cadence with a budget | §1; `AiGoalPlanExecutionJob` exists in `worker/app/jobs/`, `GoalDrivenSchedulerService` has no ticker | New `Ai::AgentDuty` (agent, skill or goal, cron, budget, policy category) + one worker cron `AiAgentDutyTickJob` → existing `execute_agent`/goal-plan path; gated by `should_execute_now?` (kill switch, duty cycle, budget). Seeded duties: hourly health review, daily drift + pending-task sweep, weekly knowledge/skill health |
| G4 | **Project as first-class noun** | §1; `Ai::Mission` already carries repo, scaling bounds (`mission.rb:15-99`), `ProjectMetric`; frontend has Missions under AI, no Projects | Core `Ai::Project` (account, name, slug, repo, template, budget/bounds, SLOs, owning team) with `has_many :missions`; the provisioning brief creates or attaches one; `platform.project_list/get/status/health` verbs; a Projects page that is the operator's top-level view of "things I run" |
| G5 | **Per-project team + skills** | Hierarchy P4 seeded `TeamTemplate`s (System Operations, Platform Engineering) exist on the branch; nothing instantiates a team **per project** | On project create, clone a canonical "Project Operations" TeamTemplate (observer, deployer, SRE roles from canonicals) scoped by delegation policy + bounds; the team owns the project's workload sensor and receives its standing signals |
| G6 | **Workload sense** — the platform still observes the infrastructure, not the workload it deployed | readiness doc §3 still true: no sensor names `ProvisioningCodeDeployment`/`DockerHost`; only `memory_pct` + replica/region counts are live | `WorkloadHealthSensor` over the `verify:` probe channel and heartbeat runtime block; cpu/latency/availability producers into `ProjectMetric` |
| G7 | **One front door** | Two concierges: core "Powernode Assistant" (what the floating widget opens via `conversations#create_concierge`) delegates to the extension's "System Concierge" through `ConciergeRouter`; the seed skill is named "Powernode Concierge"; Claude Code's `powernode-assistant` skeleton calls itself "intelligent concierge" and `system-concierge` is separately listed | Keep the two-tier routing; present ONE name ("Concierge") in UI, skeletons and docs; a `/powernode status` skill (health + pending approvals + standing signals + open questions) |
| G8 | **Claude Code surface** | 32 skeletons, 405 KB, ≈12.6 KB each of raw tool lists; this cell's instance grant lacks `platform.route_task`, `describe_tool`, `list_agents`, `get_system_health` while the SessionStart hook says "ask platform.route_task when unsure" (`session-guidance-inject.sh:40`) | Skeletons carry tool **families**; SessionStart advertises only tools the connector actually lists; grant call (paste-ready in `instance-principal-grant-survey-2026-08-15.md`) extended with the routing/read verbs |
| G9 | **Consolidation** | 4 core monitoring agents (System Performance Monitor, System Health Monitor, System Analytics Intelligence, System Quality Assurance) + canonical Infrastructure Health Monitor own no sensor, policy or schedule; duplicate seed names: Release Manager ×3, Skill Manager ×2, Design Agent Team/Skill From Intent ×2, PRD Generator ×2, Platform Architect/Developer ×2 (core seeds vs hierarchy seed); README says 21 sensors / 50 executors / 12 jobs, tree has 36 / 65 / 10 | One Platform Health Monitor owning G1's sensor; QA stays under Engineering as reviewer; a spec/docs guard that regenerates README counts from the catalog |
| G10 | **Configurability** | 4 of 36 sensors have `get_sensor_config` entries | Register the rest through the same `SENSOR_CONFIG` seam (DB-driven thresholds per memory `feedback-no-hardcoded-budgets-configurable`) |

Not re-opened here (already built on the branch, awaiting deploy): replace/reap instance, promote
replica, restore volume, snapshot policy, governance-gap sensor, canonical team templates, route_task.

## 4. Proposed campaign — "Autonomous Project Platform"

Seeded increments (consumer-first; each increment ends in an actuator or an operator, never a returned
plan):

0. **Deploy 4 + grants + egress** (operator-run, tracked): deploy the branch; add
   `platform.route_task`, `describe_tool`, `list_agents`, `get_system_health`, `record_agent_execution`,
   `dev_update_task` to the dev-cell instance grant with `mode:"add"`; confirm the account's
   `protected_egress_hosts` includes the AI provider hosts; re-run the §2 smoke as the admin user.
1. **Composite platform health** (G1) — producer, persistence, one verb, Health page, concierge answer.
2. **Standing-signal hygiene** (G2) — age/escalation, inbox routing, errored-ephemeral reap lane, the 12
   config-drift assignments and 11 errored instances resolved by the new lane, not by hand.
3. **Agent duties** (G3) — `Ai::AgentDuty` + tick job + four seeded duties on canonical managers.
4. **Project noun** (G4) — model, verbs, page, brief → project attachment.
5. **Project team + workload sense** (G5, G6) — per-project team from a TeamTemplate; WorkloadHealthSensor;
   cpu/latency/availability producers.
6. **One front door** (G7, G8) — naming, `/powernode status`, slim skeletons, grant-aware SessionStart.
7. **Consolidation** (G9, G10) — monitoring-agent merge, duplicate seed names, README guard, sensor config.

Decision authority: `supervised` (schema + agent-roster changes). Driver: Claude Code. Scope: core +
system extension. Stop conditions: any increment that needs a policy ruling parks a question; §7 of
the readiness doc is never crossed.

## 5. Offers filed alongside this report (individually, for individual approval)

See the improvement queue: health_check coverage lie; per-tick `deduped` FleetEvents; `list_instances`
lacks a status filter; `GoalDrivenSchedulerService` has no ticker; SessionStart advertises an ungranted
verb; README counts drift; monitoring-agent duplication.

## 6. Questions for the operator

1. **Admin smoke.** How should I obtain an admin bearer token for ops-hub — paste one as
   `AI_SMOKE_TOKEN`, or arm break-glass and mint via `scripts/ai-smoke/mint_token.rb` on the hub?
   And is the AI provider host on the account's egress allow-list?
2. **Deploy 4 before anything else?** Recommended yes; the hierarchy and DR work is undeployed.
3. **Project noun shape.** New core `Ai::Project` with `has_many :missions` (recommended) versus a facade
   over the infrastructure mission.
4. **Duty budgets.** Scheduled agent runs count against the same consent budget as autonomy ticks
   (recommended), unlike Claude Code runs (P1c ruling).
5. **Monitoring-agent merge.** Merge Performance/Health/Analytics/Infrastructure monitors into one
   Platform Health Monitor; keep System QA under Engineering. Any to keep separate?
6. **Public-demand priority.** "Git URL → running, exposed, monitored, with a team" first (recommended),
   before multi-cloud SDK gems or Kubernetes depth.
7. **Front-door name.** Present a single "Concierge" to users, with System Concierge as an internal
   specialist?

---

## 7. Deploy 4 and the post-deploy smoke (2026-09-05, executed)

Operator approved all seven §6 recommendations and directed deploy 4 before the campaign.

**Deployed.** `develop` = `cd7fe58c6` (merge of the loop branch; submodule → `f23d94d9`), pushed to
Gitea and GitHub, extension first so the module-forge clone could not pick up a stale tree. Native
batch `01a06ff7` planned three modules off the core range and promoted them batch-atomically:
hub-backend v95, extension-system v86, hub-frontend v30. Verified by content on the node, not by
version number: `/api/v1/version` → `cd7fe58`; `SnapshotPolicySensor` present in the extension
layer; `cache_versioning.rb` present in the core layer; `index.html` rewritten at 05:21:51, so the
v29 stale-index defect did not recur; `/up` 200; zero pending migrations. Seeds re-run: 12 domain
agents attached under the concierge root, System Operations team seated at 12, 128 skills synced.
Dev-cell instance grant widened 22 → 27 patterns and confirmed live. Break-glass revoked.

**The deploy auto-applied the parked audit-scrub migration.** `20260905050000` was recorded as
applied during the restart (ops-hub auto-applies pending migrations on boot), before its parked
task was dispositioned. Effect measured: 2 rows scrubbed to `[FILTERED]`, 0 rows still holding a raw
value under an `email` key, 304 User-type audit rows and 34,887 total rows otherwise untouched, and
0 KubernetesCluster rows existed to scrub. The change is irreversible by design. This is a process
finding as much as a data one: a migration parked for human review shipped and ran because parking
gates the COMMIT, not the DEPLOY.

**The smoke found the sharpest evidence for increment 1.** Asked "how many node instances are
currently in error status, and which agent owns fixing them?", the account Concierge replied
"Currently, there are no node instances in error status" — while 12 were. It read
`get_system_health`'s `errors` block (AI *execution* errors over 24h, from `Ai::ExecutionEvent`) and
presented it as fleet health. Filed as `01a07024-d980`; it is the acceptance case for the composite
health producer. Two secondary observations from the same run: no `Ai::AgentExecution` row was
written for a live agent turn, and the Concierge answered a fleet question inline rather than
delegating, though `platform.route_task` ranked correctly when asked directly (Capacity Manager
0.762 for a DR task, with per-dimension reasons).

**A provider deadlock blocked using the operator's own credential.** Activating a provider validates
`supported_models`; the only sync path visits active providers only. Anthropic and Grok both held
live credentials and neither could be activated, so every agent ran on the one active provider.
Broken by calling the per-provider sync directly (11 models fetched), then activating. Filed as
`01a07025-24b6`.

**Campaign started:** `01a07025-5780-7b34-b7e9-6d844ebe4599`, 8 increments, supervised, branch
`campaign/01a07025-5780-7b34-b7e9-6d844ebe4599`. Increment 0 recorded passed.

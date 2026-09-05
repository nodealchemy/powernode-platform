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

> **Historical.** This is the plan as first proposed, kept for the record. What was actually
> built, and where it diverged, is section 8. Two items here did not survive contact: the duty
> plane was built as one real scheduled duty rather than four seeded ones, and the workload
> sensor was deliberately NOT built because a precondition check found the gap was elsewhere.

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

> **Historical.** These are the questions as first asked, kept so the rulings have their context.
> All seven were answered and acted on during the session. The decisions still open are in
> section 9, which supersedes this list entirely.

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

**That second observation was attributed wrongly, and the correction matters more than the
original.** It was written up as the Concierge choosing not to delegate. A later measurement of
the routing path suggests it may not have been a choice. The router that runs before the model
builds its delegation candidate set from agents typed as assistants, and nearly every platform
specialist is seeded as a monitor. If that holds, no monitor can ever be selected, system-domain
delegation collapses onto the single assistant-typed agent in that domain, and the routing verb's
ranking is a preview of something the router cannot act on. A ranking that cannot be acted on is
worse than no ranking, because it looks like the feature works. The mechanism is filed as
recommendation `01a0705e-cd38`, and the driver has since confirmed it directly rather than
relaying it.

The candidate set is built in the concierge router and applies two filters, not one. Any skill
whose domain is platform yields an empty candidate list before agent type is considered at all,
and what survives that is then narrowed to agents typed as assistants and currently active.
Across the system extension's own agent seeds, ten declare a monitor type against two assistants,
so ten of that domain's specialists cannot be delegation candidates under any circumstances,
however well they rank. The driver first wrote three assistants, having counted a core canonical
seeded elsewhere as one of the domain's specialists; the corrected ratio is worse than the one
first reported. The specialist the routing verb named in the incident is among the ten, its
monitor type declared in its own seed, so the agent-type exclusion definitely applies to it.

The divergence turns out to be sharper than a filter being too narrow. The two paths share the
same ranker: the concierge router calls the very service that sits behind the routing verb,
passing the conversation's agent as delegator so the delegation policy binds identically. What
differs is the candidate list handed to that ranker. Called directly, the verb ranks across a wide
pool and names a specialist. Called through the concierge, the same ranker receives a pre-filtered
list that may be empty. The two agree on everything except the one input that decides the outcome,
and nothing about the difference is visible from either side.

Which of the two exclusions actually fired in the smoke test is unproven. Either alone explains the
inline answer, so the finding stands regardless, and it is recorded as unproven rather than
resolved by picking the likelier one.

**A parallel review then found a third cause, and it is probably the primary one.** The driver had
settled on the candidate filters as the explanation. They are real, but they are not the whole
story, and the framing was again too confident. The router's DEFAULT exit is to answer inline, and
a fleet-status question reaches that exit for a reason that has nothing to do with either filter:
those skills take an operation argument, which makes them neither automatically invokable nor
delegable, so the question never becomes a delegation candidate in the first place. The agent's
own prompt then lists status checks as the inline case explicitly. So three causes stack, and the
correct route existed in the same file the whole time, because the router's delegated exit already
calls the very ranker behind the routing verb. It simply never fires for this question shape.

One further consequence, which is why the incident could not be reconstructed from records: a chat
turn writes no execution row at all, since only the tool-invoked paths write one. The answer was
therefore unauditable after the fact, and the agent never accrues the performance history that its
own routing score partly depends on.

**A provider deadlock blocked using the operator's own credential.** Activating a provider validates
`supported_models`; the only sync path visits active providers only. Anthropic and Grok both held
live credentials and neither could be activated, so every agent ran on the one active provider.
Broken by calling the per-provider sync directly (11 models fetched), then activating. Filed as
`01a07025-24b6`.

**Campaign started:** `01a07025-5780-7b34-b7e9-6d844ebe4599`, 8 increments, supervised, branch
`campaign/01a07025-5780-7b34-b7e9-6d844ebe4599`. Increment 0 recorded passed.

---

## 8. Campaign progress (as of 06:45 UTC, four concurrent implementation lanes)

Work is split across four lanes on disjoint file sets, each with its own test database and a
shared commit lock. The driver reviews every diff before an increment is recorded, after the
lane commits, because a mid-flight working-tree read cannot tell a finished change from a
pre-review pass.

| Increment | Lane | State | Landed as |
|---|---|---|---|
| 0 — deploy 4, grant widening, provider egress, admin smoke | driver | passed | `cd7fe58c6`, `6b809c777` |
| 1 — one composite health producer | A | passed | `a4e48913`, `68fa275e` |
| 1b — the fourth health surface delegates to it | A | passed | `4cecd91b` |
| 2 — standing-signal hygiene | B | passed | `16b50d34`, `20de8ab8`, `9cd594e5`, `45fa9b1a` |
| 3 — one real agent duty, scheduled and attributed | D | passed | `9fb06bd6`, `833bdef62`, `b6b9e007` |
| 4 — `Ai::Project` as a first-class core noun | C | passed | `e6fee942f`, `f9a7abe31`, `b2cf87c4b`, `4d46560d2` |
| 5 — per-project team, core half | C | passed | `abf47cb1a`, `71d38371b`, `2151a47e1`, `d66bf1607` |
| 5b — workload sensor: NOT built, gate found the gap elsewhere | B | passed as a report | — |
| 5c — availability absent-vs-zero, consumer side pinned | B | passed | `bf703913`, `afbce91e` |
| 6 — one front door: resolution moved, then renamed | A | passed | `295742ba`, `0a55bcd7`, `3d9d9edee` |
| 6b — a teamless project says WHY it has no team | C | passed | `2e2f3268c`, `3c721d80d` |
| 7 — docs and prompts asserting false counts | D | passed | `3927ed0b`, `ecbdbab4b`, `3f12a7b62`, `fc3dd976d` |
| 7b — duplicate seeded-name audit, zero live defects | D | passed | `0665982e2` |
| 8 — the no-bare-fact rule as a baselined lint | C | passed | `bcddaa4b4`, `32ed1f579` |
| 9 — metric-declared-vs-sampler-measured census | B | passed | `59e3fc14` |
| 10 — project SLO targets resolve, and can be declared | C | passed | `f2dc2ed72`, `9c6fec7d9` |
| 10b — the write states the consequence it enabled | C | passed | `cc87b2ca8`, `58cf62ce3` |
| 10c — the sensor half and its end-to-end oracle | B | dispatched | — |
| 11 — smoke count derived; allowlist claim overturned | D | passed | `5a3c1e70` |
| 11b — close the six-row roster gap | D | dispatched | — |
| 12 — make an undeclarable target visible, and fix the note | B | dispatched | — |

Twelve defects were filed rather than fixed, each with its mechanism at a file and line: the
unfenced boot-image rollout, the delegation candidate filter, a blank permission list meaning
unrestricted, a project team an operator cannot edit, an account destroy that raises partway,
promotion-advisory failures that read as a silent refusal, project targets bypassing the ladder,
a project archive that protects nothing beside a cleanup that detaches account-wide, two agents
both resolving from the word concierge, every unconfigured canonical exporting one allowlist, an
absence note that misreports two metrics, and a freshness check that cannot tell a dirty tree
from a stale artifact.

Three driver errors were caught by the lanes or by re-measurement, and are recorded here because
the pattern matters more than the individual mistakes. The driver told lane A that no platform
health controller existed; it does, and the driver's search had used the filename from the stale
comment rather than the real class. The driver recommended deleting a network as a zero-peer
decoy; re-measurement found two peers and two heartbeating VMs, so the critical alarm on it is
true and the recommendation was withdrawn. The driver attributed the SDWAN failure to a
29-minute race; both nodes in fact report the promoted image sha, and the real cause is that no
boot image has been built since before the fix landed. In each case the brief was the defect.

The deferred integration step is done, and the thing the driver was trying to prevent happened
anyway. The driver had told every lane not to regenerate the MCP tool catalog or the Claude Code
agent skeletons, intending to reconcile both once at the end, precisely because a regeneration
reads the working tree and can bake another lane's uncommitted edit into a committed artifact.

Two lanes regenerated regardless, and the driver's first account of it was wrong. The driver
initially recorded that no contamination occurred because the one concurrent description change
had already been committed. Lane A then supplied the timestamps that settle it: lane A regenerated
the catalog at 06:29 while lane C's tool file was still untracked, and committed that catalog at
06:32:59; lane C committed the tool itself at 06:36:51. So the catalog commit documents code that
was uncommitted when it was read and landed roughly four minutes before that code did. The two
commits are ordered wrongly in history. The artifact is correct today only because the code
followed it, which is luck about ordering rather than a property of the process.

Lane C separately regenerated both artifacts again when landing its verbs, and its regeneration
also carried lane A's health-snapshots table into `schema.rb`, which it could not render without.
Lane C flagged this in its own report rather than leaving it to be found.

The reconciliation nonetheless verifies clean. Measured after the fact: the agent-skeleton
freshness gate passes silently, and `scripts/pattern-validation.sh` run from the repository root
reports fifty-three checks, zero failures, zero warnings. Both of the outstanding failures are
closed. The lesson is not that the instruction was unnecessary. It is that an instruction not to
touch a generated artifact cannot hold when a lane's own verification requires the artifact to be
current, so the next parallel run should either give one lane ownership of every generated file or
accept that generation happens continuously and pin it to committed state instead.

## 9. Decisions the operator still owns

Nine, in the order they block work. Decision 0 is a precondition on decisions 1 and 2 and was
found after the rest were written, which is why it carries a zero rather than renumbering them.

0. **Set the self-management fence before any image is promoted.** This one is new, it reorders
   the rest, and the driver verified all three of its legs independently rather than relaying
   them. First, the boot-image drift rollout executor includes no fence at all; the mixin that
   six other services include is absent from it, and the executor's own declared blast radius,
   written into its skill registration, is that it reboots every drifted node on the platform,
   batch by batch. Second, the fence is inert until a site setting names the self-hosted node,
   and that is not an inference: the code's own comment says the setting is unset on every plane
   today and that setting it is an operator action deliberately not performed. Third, the control
   plane is drifted right now, confirmed by a live read of its instance, which reports boot-image
   drift true with a booted revision that differs from the promoted one.

   So the composition is not hypothetical. Promoting a new image makes every node drifted at
   once, including this one, and the only thing standing between that and an automatic reboot of
   the machine the control plane runs on is that no rollout has been triggered since. Approving
   decision 1 without this authorises the reboot. Setting the setting and teaching the rollout
   executor to honour it is a precondition, not a nicety.
1. **Publish an amd64 disk image carrying `fe5c8da4` and set it default.** Nothing in SDWAN can
   be observed until this lands. It auto-promotes fleet-wide, and decision 0 must land first.
2. **Publish a `powernode-system-base` version carrying `28460bbb`.** This is what makes an
   apply failure visible per subsystem instead of silent. It auto-promotes fleet-wide and
   reaches the control plane itself, so the boot window needs watching.
3. **Node budget on `dna`.** Four small nodes at two virtual CPUs and two gigabytes, with the
   lightweight network profile set explicitly, rather than reusing the current sixteen-gigabyte
   type. Memory, not disk, is the constraint on this host.
4. **Keep flow export, OVN and federation out until phase 3**, entering only as node modules
   plus, for cross-plane federation, a second control plane virtual machine. Each is a separate
   approval.
5. **Disposition of the audit-scrub task** whose migration already ran during the deploy-4
   restart before the task was reviewed.
6. **Reaping the dead CI builders, and the count I gave you was wrong.** I said nine. A
   re-measurement found a messier picture: eleven instance rows in error and four stopped, two
   virtual machines running with no platform row at all, one running behind an error row, and a
   sixteen-gigabyte cell in a starting state that has not sent a heartbeat since 2026-08-10.
   Those are four different conditions needing four different dispositions, not one bulk reap.
   It is well past the five-item threshold, so it needs your explicit confirmation against a
   list rather than a number, and I will put that list in front of you rather than act on the
   category. Nothing in the proving ground depends on it; the memory it would free is not needed.

7. **Whether to deploy today's work, and I recommend not yet.** Fourteen increments have landed
   across core and the extension, every one spec-green, and not one line of it is running on the
   control plane. Deploy 4 this morning predates all of it. I have not deployed and will not
   without you, for a specific reason rather than caution in general: today's changes span BOTH
   core and the extension, and the recorded outage in this platform's history is exactly that
   shape. The extension builds roughly ten times faster, promotes on its own, and a new extension
   against an old core is a crash loop, with the rollback tool unavailable because the thing that
   would run it is the thing that is down. The commits are also still local; nothing is pushed.
   The safe sequence is push both, build both, and promote core first, watching the boot window.
   That is a decision with a real failure mode attached, so it is yours rather than mine.

   Three consequences land the moment it deploys, and none is a defect. A mission that declared an
   availability target of zero has been silently unmonitored, because zero is truthy in Ruby so it
   survived the fallback and the arm could never fire; those missions will start reporting real
   breaches. An unusable cost declaration no longer falls through to the provisioning brief's cap,
   because the reader stops at the first rung that speaks. And an availability figure outside the
   valid range now resolves to not-declared and falls back to the default instead of being honoured
   verbatim. All three are correct behaviour arriving suddenly, which is its own kind of event and
   is worth watching for rather than being surprised by.

   Two further things travel with it. The rename's backfill has run only on lane and development
   databases, so the live control plane still carries the old agent name until it is applied. And
   the subagent handle has already moved, so anything holding the old one is broken now rather than
   resolving quietly to a stale row.

8. **Whether a project's declared ceilings need a magnitude brake, and where it sits.** This is a
   money question rather than a defect, which is why I am not deciding it. A project can now
   declare service-level targets, and the surprising direction is the tight one: lowering a CPU
   ceiling makes breaches fire more often, a breach maps to a scale change the adaptation gate
   seeds for auto-approval, so a small number raises the rate of spend-incurring proposals.
   Three things bound the consequence today and none of them is the write itself. Auto-apply
   requires a window declared elsewhere that this verb cannot write. The composer's auto-apply
   verdict allows only the additive strategy, so nothing reaches the removal arm. And removals
   need an operator approval regardless. What is missing is any rate or magnitude limit on the
   declaration: a caller holding the manage permission can set an aggressive ceiling on a project
   whose window is already open, and nothing in the write path objects. I declined to invent a
   floor, because picking a threshold here would be hardcoding a budget-shaped constant on a
   guess. Instead the write will now tell the caller whether that project's window is open, so
   arming continuous spend and doing something harmless stop returning identically. Whether a
   real floor should exist is yours.

**One finding is not a decision but should be read before any of them.** Archiving a project is
refused by nothing and observed by nothing: no loop reads project status, so convergence, upgrade
and pool replenishment all continue on the nodes of a project the operator believes is finished.
The statuses have no writer at all today, so the transition cannot even be made through the
product. The dangerous half is what an operator would do next. Disabling the project's modules is
the obvious cleanup, and the node-facing desired-state endpoint filters the enabled scope
module-wide, so it removes those modules from every node in the account, and the agent reconciles
a missing module by detaching it. That is the exact mechanism of the 2026-07-28 control-plane
self-detach, and the comment directly above that line narrates it. The fail-closed guard added
afterwards protects against an incomplete list, not against a module deliberately disabled, which
is indistinguishable from an intentional unassignment. Verified at source rather than relayed.
Filed as `01a07071-1aee`. No automated path may disable modules.

Four campaign proposals now await approval, all supervised and none started: the SDWAN fabric
`01a07051-8d33`, the wider proving ground `01a07058-12b0`, the no-bare-fact rule `01a07065-46ed`,
and project infrastructure `01a07071-682c`. Decisions 0 through 4 are the gates on the first two. The wider proving ground, of which SDWAN is one
part, is proposal `01a07058-12b0-7832-a80f-f5ca5903001e` and is designed in
`docs/reference/proving-ground-design-2026-09-05.md`: seventy-two capability rows each with a
positive oracle, of which forty-six are provable on this hardware today, sixteen need one of the
decisions above, and ten cannot be proven here at all. Thirteen new instances at thirty-two
gigabytes cover phases one and two, against 104 free.

Three capabilities cannot be proven safely as things stand, and this is the finding I would most
want you to read. Ingress and certificates cannot be exercised without writing into the control
plane's own live proxy configuration, because although a reverse-proxy module exists, no writer
targets a node. Disk-image promotion and boot-image rollout share a single platform default with
the control plane and run through an unfenced executor, which is decision 0 above. Volume snapshot
and restore never reaches its copy-swap path at all, because the Proxmox adapter declares no
snapshot support, which is a separate thing from the known storage wedge on this host and would
still be true if that wedge were cleared.

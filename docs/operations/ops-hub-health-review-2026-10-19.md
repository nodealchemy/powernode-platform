# ops-hub health review — 2026-10-19

> **Status:** report only. Nothing on the hub was changed: no restarts, no DB/Redis/platform writes, no decision,
> notification, proposal, task or autonomy action was approved, dismissed or executed. One read tool had a
> persisting side effect, disclosed in §0.3.
> Deployment identifiers are placeholders (`<ops-hub-host>`, `<hub-vmid>`, `<pve-host>`, `<gitea-host>`, ...);
> the mapping lives in platform knowledge (`search_knowledge tags:["deployment-ops-hub"]`). Row UUIDs appear only
> where the bulk-operation rule (count + first 3 + last 1) requires them.

Review window: 2026-10-19 14:03Z–14:25Z. Sources: `mcp__powernode__platform_*` read verbs, `ssh pnadmin@<ops-hub-host>`
(no sudo), read-only `psql` over TCP (`SET default_transaction_read_only=on`), `redis-cli` reads, and the local
checkout for code references. Companion documents: `fresh-install-findings-2026-10-19.md` (findings `#1`–`#25`,
filed as `[fresh-install #N]` proposals), knowledge `incident:dev-cell-reaped-2026-10-15`.

---

## 0. Summary

### 0.1 Headline findings, ranked

| # | Urgency | Finding | Recommended option (details in §17) |
|---|---------|---------|-------------------------------------|
| 1 | **now** | **No working database backup.** The nightly `daily_database_backup` has left 20 `database_backups` rows in `pending` (12 in Sep, 8 in Oct; none ever completed). The only dump on disk is a manual one from 2026-09-26 (3.0 GB, root-owned). | Take a hypervisor snapshot/`vzdump` of `<hub-vmid>` today, then fix the worker backup path (§13, option B). |
| 2 | **now** | **The control plane was down ~10 of the last 14 days.** Fleet-tick gaps: 10-06 (15 h), 10-07→10-08 (20 h), 10-09→10-15 (5 d 8 h), 10-15→10-19 (4 d 2 h). Current boot 09:28Z today. Cause is not visible from an unprivileged shell. | Pull the journal via QGA and re-arm the external watchdog (§2). |
| 3 | **now** | **The scheduled platform-health sweep has been silent since 2026-09-19 21:25Z** (1,051 snapshots up to then, zero after). The worker job ticks every 5 min but the server skips every tick with `no_bound_agent_clone` because the `platform-health-monitor` global agent is missing (also reported by GovernanceGapSensor). All 10 platform-subsystem component rows sat at `SnapshotStale` for 30 days and produced 4,150 "X is degraded" notifications. | Seed the missing canonical agent (code/seed path) and, until then, run `system_platform_health_check` manually (§4). |
| 4 | **now** | **Server and worker disagree on the Sidekiq Redis DB.** Sidekiq registers in Redis DB 0; the server derives its "worker Redis" as DB 1 (`server/config/initializers/redis.rb:122-128`). Result: the `Sidekiq` core component has read `down` since 2026-09-26 (false), and any server-side enqueue lands in DB 1 where nothing consumes it (1 stranded `SystemPackageRepositorySyncJob` from 08-22). | Set `SIDEKIQ_REDIS_URL` on the Rails unit to DB 0 (root via QGA) (§3). |
| 5 | **now** | Hub `System clock synchronized: no`, no NTP service. mTLS, JWT and ACME all depend on time. | Verify chrony/timesyncd in the hub image; add to the boot checks (§14). |
| 6 | **this week** | **Noise:** 20,910 unread notifications (20,868 dismissable), 39 open governance reports re-minted every 6 h with no dedupe, 8,924 expired approval requests, ~17–47k fleet events/day from a handful of standing sensors on subjects that no longer exist or are stopped test VMs. | Approve the cleanup plan in §10 (stop-the-source first, then bulk dismiss). |
| 7 | **this week** | 17 pending approvals, 16 of which expire 1–4 h after minting and are re-minted next tick; 3 are destructive reaps of stopped dev VMs. | Decide the 7 stale live instances once (§6, §8). |
| 8 | **this week** | Fleet-events table is 20 GB of a 23 GB DB; 31.2 M of 32.0 M rows are older than 30 days; retention is 90 days by env default. `/persist` is at 79 %. | Lower `POWERNODE_FLEET_EVENT_RETENTION_DAYS` to 30 (root env) (§12). |
| 9 | **this week** | Reaper lane (`system.abandoned_instance_reap`) still auto-approves `error`-status guests — the lane that destroyed the dev-cell (`[fresh-install #16]`). INV-1 **is** armed (knowledge entry saying otherwise is stale). | Keep #16 at P1; gate the lane on provider power state (§16). |
| 10 | later | Record hygiene: 22 terminated instance rows, 31 node rows (11 CI builder nodes), 17 unrevoked certs on terminated instances, 6 `docker_host` component rows for 08-09 dry-run cells, 2,678 stale signal states, 5,378 dead Sidekiq jobs. | Archive/prune per §12 (C8 backlog hygiene). |

### 0.2 Counts at a glance

| Metric | Value |
|---|---|
| Notifications total / unread / dismissable-as-stale | 20,919 / 20,910 / 20,868 |
| &nbsp;&nbsp;by type (unread) | approval_required 8,963 (8,946 point at non-pending requests) · agent_status_update 5,776 · system_alert 4,976 · agent_escalation 1,157 · agent_proposal 25 · ai_plan_review 13 |
| Pending approval requests | 17 (16 minted today, 1 from 2026-09-21 with no expiry) |
| Approval requests all time | 8,924 rejected (expired) · 30 approved · 17 pending · 22 deferred-op approved |
| Deferred operations pending | 0 |
| Governance reports open | 39 (30 resource_abuse, 5 policy_violation, 4 anomaly), last created 2026-09-30 |
| Sidekiq dead / retry / scheduled / queues | 5,378 / 0 / 0 / all empty |
| Fleet events | 32,013,789 rows, 20 GB (13 GB heap + ~5 GB indexes); 31,180,951 older than 30 d |
| Component statuses unhealthy | 21 of 118 rows (6 docker_host not_measured, 2 sdwan_peer down, 1 core_service down [false], 1 remediation_effectiveness degraded, 1 platform_subsystem degraded, 3 not_measured, ...) |
| Instances | 32 rows: 2 running, 1 pending (stub), 1 rebooting (since 09-12), 6 stopped, 22 terminated |
| Silent instances (180 s threshold) | 30 reported, but 22 are terminated rows; **0 live instances are actually silent** |
| Certificates alerting | 3 node-cert rows (2 superseded hub certs, 1 on the reaped dev-cell), all already replaced |
| Health snapshots | 1,051 between 09-06 and 09-19; 0 from 09-19 21:25Z until this review's call |
| DB backups | 20 rows pending, 0 completed; last file on disk 2026-09-26 |

### 0.3 Side effect disclosure

`mcp__powernode__platform_system_platform_health_check` (listed as a read verb in the brief) persisted a
`System::PlatformHealthSnapshot` (`persisted: true`). The next status sweep (14:08Z) consumed it and moved the ten
`platform_subsystem` component rows from `SnapshotStale/degraded` to their live verdicts (7 ok, 3 not_measured,
1 degraded). No other call wrote anything. This is also direct evidence for finding #3: the probe works when
invoked; only the schedule path is broken.

---

## 1. Method and access

- MCP read verbs used: `health` (returned `null`), `get_system_health`, `alerts` (`null`), `list_component_status`,
  `get_notifications`, `list_deferred_operations`, `governance_dashboard`, `list_governance_reports`,
  `kill_switch_status`, `provider_health` (`null`), `integration_health`, `system_get_silent_instances`,
  `system_list_instances`, `system_list_nodes`, `system_list_instance_pools`, `system_list_tasks`,
  `system_recent_signals`, `recent_events` (`null`), `metrics` (`null`), `get_approval_request` (4 ids),
  `system_get_sensor_config`, `list_improvements`, `campaign_list`, `list_audit_logs`, `migration_status`,
  `search_knowledge`, `system_platform_health_check` (see §0.3).
- Four verbs (`health`, `alerts`, `provider_health`, `metrics`, `recent_events`) return `{"result":null}` on the
  hub: either not wired for this principal or broken. Worth a `[streamlining]` note; not investigated further.
- Shell: `systemctl`, `df`, `free`, `uptime`, `ss`, `openssl s_client`, `curl`, `redis-cli` (reads; job args never
  printed), `psql` read-only over TCP. `journalctl`, `/persist/redis`, `/persist/var/lib/postgresql` and
  `/persist/powernode-rails/*.conf` are root-only and were not read.

---

## 2. Availability history (new finding)

Fleet ticks (`fleet.tick_complete`, 1/min) are the best uptime proxy available without the journal:

| Day (Oct) | Ticks | Events | Notes |
|---|---|---|---|
| 01–05 | ~1,440/day | ~47.5k/day | steady |
| 06 | 485 | 15,270 | gap 04:55→20:17Z (15 h 22 m) |
| 07 | 851 | 27,507 | down from 21:37Z — the fleet-wide heartbeat silence in the incident record |
| 08 | 328 | 10,201 | back 17:23Z (gap 19 h 46 m) |
| 09 | 783 | 24,491 | gap 12:08→15:24Z; down again 21:43Z |
| 10–14 | 0 | 0 | **5 d 7 h 47 m outage** |
| 15 | 109 | 4,065 | up 05:30–07:23Z only (the reaper fired at 05:41Z in this window) |
| 16–18 | 0 | 0 | **4 d 2 h outage** |
| 19 | 283 | 10,278 | up from 09:30Z (boot 09:28:08Z; `last -x` shows only this boot) |

Sidekiq daily `stat:processed` matches (nothing processed 10-10..14 and 10-16..18). The dead-set spikes
(1,752 jobs on 10-07, 3,138 on 10-09, all `BackendApiClient` circuit-breaker OPEN / `Timeout::Error`) sit at the
onset of the 10-07 and 10-09 gaps: the worker was alive and the Rails backend was not answering for a period before
each full outage. Knowledge records a hypervisor-wide "many guests stopped" event on 10-05 21:24Z.

What this means: every per-day metric below is understated, and every "no snapshot since", "no backup since"
observation must be read against this calendar. The root cause (hypervisor, VM, kernel, Rails hang, OOM) is not
determinable from pnadmin; it needs `journalctl -b -1 … -b -4` via QGA and the hypervisor's task log for `<hub-vmid>`.

Options → §17 item A.

---

## 3. Service status: units, restarts, Sidekiq, Redis

### 3.1 systemd units (module-composed names, discovered with `systemctl list-units 'powernode-*'`)

| Unit (suffix) | State | NRestarts | Started |
|---|---|---|---|
| `…-postgres` | active | 0 | 09:28:41Z |
| `…-qga` | active | 0 | 09:28:41Z |
| `…-rails-setup` (oneshot) | exited ok | 0 | 09:28:41Z |
| `…-rails` (puma 8.0.2, Ruby 3.2.8, prod) | active | 0 | 09:28:44Z |
| `…-sidekiq` (Sidekiq 8.1.6, concurrency 25) | active | 0 | 09:28:41Z |
| `…-worker-web` | active | **9** | 09:29:35Z — all 9 restarts inside the first 50 s of boot (ordering race with Rails/Redis); stable since |
| `…-caddy`, `…-traefik`, `…-restore-dynamic` | active | 0 | 09:28:41Z |
| `…-redis` | active | 0 | 09:28:41Z |
| `powernode-agent` | active | 1 | 09:28:46Z |
| `powernode-network-reload`, `powernode-ssh-hostkeys` | exited ok | 0 | — |
| `systemd-firstboot`, `systemd-sysupdate` | **failed** | — | OS units, not Powernode; cosmetic but worth a look in the image |

`/up` → 200 in 0.49 s; `/.well-known/oauth-authorization-server` → 200 but serves the SPA (`[fresh-install #14]`).

### 3.2 Sidekiq

- Process registry (DB 0): 1 process, 25 threads, 0 busy, heartbeat fresh (`beat` within 10 s), 28 queues
  listened, every queue empty, retry set 0, scheduled set 0.
- Scheduler: `sidekiq-scheduler`, 96 schedules loaded (`schedules` hash) including every `extensions/system`
  entry (`system_platform_health_sweep`, `system_fleet_event_retention`, `system_fleet_reconcile`, …).
- Lifetime stats: 1,213,841 processed / 99,516 failed. Today: 3,903 / 224 (the 224 are mostly `Git::PipelineSyncJob`).

**Dead set: 5,378 jobs** (oldest 2026-10-05 14:03Z, newest 14:02Z today).

| Failure day | Jobs | | Job class (top) | Jobs |
|---|---|---|---|---|
| 10-05 | 116 | | `Git::PipelineSyncJob` | 782 |
| 10-06 | 121 | | `System::CiRunnerLeaseReconcileJob` | 663 |
| 10-07 | 1,752 | | `MigrationChainAdvanceJob` | 609 |
| 10-08 | 172 | | `FederationHeartbeatJob` | 598 |
| 10-09 | 3,138 | | `SystemFulfillmentRequestReconcileJob` | 593 |
| 10-15 | 23 | | `AiCampaignLandSchedulerJob` | 525 |
| 10-19 | 56 | | `PlatformStatusSweepJob` | 441 |
| | | | `SystemFleetReconcileJob` | 272 |

| Error class / message prefix | Jobs | Reading |
|---|---|---|
| `BackendApiClient::ApiError` "Circuit breaker is OPEN for backend_api" | 2,866 | Rails unreachable from the worker (10-07, 10-09) — outage onset |
| `Timeout::Error` "execution expired" | 1,830 | same |
| `StandardError` "Provider API error: 404" (`Git::PipelineSyncJob`) | 602 | a Gitea pipeline/repo the sync still polls no longer exists — **ongoing** (60 in the last 5 days) |
| `Faraday::ConnectionFailed` to `<gitea-host>:443` (getaddrinfo / timeout) | 62 | DNS/connectivity to Gitea during outages — 17 in the last 5 days |
| "Runaway loop detected: 5 executions in 60s" | 6 | self-throttle fired |
| "Provider API error: 502" | 12 | Gitea 502 |

Everything except the `Git::PipelineSyncJob` 404s and the Gitea DNS failures is outage residue, not a live fault.

### 3.3 Redis DB split (finding #4)

- `redis-cli info keyspace`: DB 0 = 4,221 keys (Sidekiq: `processes`, `queues`, `dead`, `schedules`, …);
  DB 1 = 2 keys (`queues` = {system}, `queue:system` with **1 job**, `SystemPackageRepositorySyncJob`, enqueued
  2026-08-22 04:45Z, never consumed).
- Worker: `worker/config/application.rb:83` uses `REDIS_URL` (the module config evidently points it at DB 0).
- Server: `server/config/initializers/redis.rb:122-128` — `worker_url` = server URL with the trailing DB index
  replaced by `/1`, overridable by `SIDEKIQ_REDIS_URL` then `POWERNODE_WORKER_REDIS_URL`
  (`System::WorkerJobEnqueuer.worker_redis_url`).
- `System::Platform::CompositeHealthProbe#probe_sidekiq` (`composite_health_probe.rb:366-383`) reads
  `processes` from that DB 1 client → `process_count: 0` → `down` since 2026-09-26 05:10Z (component
  `last_transition_at`), 121 "Sidekiq is down"/"Redis is degraded" alerts.
- Consequence beyond the false alert: any server-originated enqueue (package repository sync, and whatever else
  uses `WorkerJobEnqueuer`) is silently lost. Only one stranded job is visible, so the path is rarely used, but it
  is a correctness bug on the hub.

Options → §17 item D.

---

## 4. App health endpoints and component statuses

`system_platform_health_check` (live probe, 14:04Z):

| Subsystem | Verdict | Evidence |
|---|---|---|
| rails | ok | in-process, boot 09:29:28Z, 0 pending migrations |
| postgres | ok | 0.45 ms, pool 30 (3 busy), DB 24.2 GB |
| redis | ok | 3.4 ms, 9 MB used of 4 GB max, 68 clients |
| sidekiq | **down (false)** | see §3.3 |
| worker_web | ok | `/health` 116 ms, redis + backend connected |
| reverse_proxy, mcp_endpoint | not_measured | `system.platform_health.reverse_proxy_health_url` / `mcp_health_url` site settings unset |
| fleet_tick | ok | last tick 55 s old (threshold 900 s) |
| ai_providers | not_measured | 0 executions in the last hour (OpenAI, Anthropic credentials active; Grok credential active; Ollama / Claude-Code scope credential-less) |
| fleet_instances | degraded | 32 rows, 7 "silent" at the 900 s threshold — all 7 are stopped/terminated/pending rows (§8) |
| acme | ok | 0 ACME certificate rows |
| sdwan | ok | 1 network, 0 VIPs, 0 BGP sessions |
| federation | ok | 0 peers |
| status_contributors | ok | 13 kinds registered at boot |

Migration status: 170 applied, 0 pending in both paths; `schema.rb` (20260929121500) lags the DB
(20261001120000) and one DB-only version (20260904175500) exists — already `[fresh-install #7]`.

**Component status plane** (`platform_component_statuses`, 118 rows, 21 unhealthy before the §0.3 refresh):

| Kind | Verdict | Rows | Assessment |
|---|---|---|---|
| platform_subsystem | degraded (SnapshotStale) | 10 → now 1 degraded / 3 not_measured / 7 ok | **Stale for 30 days** because the scheduled sweep never ran (finding #3) |
| core_service `sidekiq` | down | 1 | false (§3.3) |
| docker_host | not_measured "NeverSynced" | 6 | Docker hosts that belong to the 2026-08-09 dry-run ops-cells, all terminated — stale rows |
| sdwan_peer | down "Lost" | 2 | `sdwan-test-a/b` peers on `dryrun-fabric`, VMs stopped since 10-05 — stale test fabric |
| remediation_effectiveness `fleet_remediation` | degraded "RemediationStuck" | 1 | 200 fingerprints at/above the stuck streak of 3 — mostly `module_assign` on stopped instances (§9) |
| node_instance | held | 6 | the 6 stopped instances (intent, not fault) |
| node_instance | progressing | 2 | the stub `dev-cell-instance-i4m3` (pending) and the builder "rebooting" since 09-12 |
| ai_provider | held | 2 | Ollama and the Claude-Code recording scope, no credential — intent |

Why the sweep is silent (`extensions/system/server/app/services/system/platform/scheduled_health_check_service.rb`):
`run_if_due!` (l.143) → `bound_agent_clone` (l.215) → `bound_canonical` resolves the executor's `binds_to
"platform-health-monitor"`; `GovernanceGapSensor` reports exactly that binding as `binding_agent_unknown`
("names no global agent", file `extensions/system/server/app/services/system/ai/skills/skill_bindings.rb`).
With no canonical, the tick returns `reason: "no_bound_agent_clone"` and the worker (`system_platform_health_sweep_job.rb:40-48`)
logs and returns — no retry, no dead-set entry, no alert. The last `ai_agent_executions` row of any kind is
2026-09-30 15:22Z.

Options → §17 item C.

---

## 5. Notifications and alerts

20,919 notifications, 20,910 unread, 20,904 undismissed. By month: Jul 1,349 · Aug 3,028 · Sep 12,317 · Oct 4,225.

| Group | Unread | Real / noise / stale | Root cause |
|---|---|---|---|
| `autonomy_approval_required` "Approval needed" | 8,963 | **8,946 stale** (their request is already rejected=expired or approved), 17 live | Decision TTL 1 h / 4 h (`fleet_autonomy_service.rb:1034 decision_ttl_for`), `ai_approval_expiry` rejects, next tick re-mints a new request + notification; the old notification is never resolved. Already filed as improvement `01a0fd18` ("re-mint an approval every ~5h"). |
| `agent_status_update` "Fleet acted automatically: …" | 5,776 | noise (informational) | `notify_and_proceed` gate writes an inbox row per action (`fleet_autonomy_service.rb:1014`). 4,321 are `module_assign`, 619 `node_lkg_investigate`, 572 `sdwan_apply_investigate`, 179 `sdwan_credential_refresh`. |
| `system_alert` "X is degraded / down" | 4,976 | **4,150 stale** (10 subsystems × 415 hourly re-alerts from the SnapshotStale period), 583 fleet_instances, 121 Redis, 121 Postgres, 1 Sidekiq | `Platform::Status::Escalation` re-notifies every `platform.status.notify_interval_minutes` (default 60, `escalation.rb:67-68`) while a row stays unhealthy; the underlying rows were stale for 30 days (§4). |
| `agent_escalation` "Standing fleet signal needs a decision" | 1,157 (985 warning, 172 critical) | mostly stale; the subjects are listed in §9 | standing-signal escalation after 60 ticks; re-escalates (53 escalations on `node_lkg_unarmed` alone). |
| `agent_proposal` `[fresh-install #N]` | 25 | **real** — keep | filed today |
| `ai_plan_review` | 13 | stale (missions from 2026-08-08/09) | — |

Alerts via `platform_alerts` returned `null`; alert state is carried by the component plane (§4) and the standing
signals (§9).

---

## 6. Pending decision and approval backlog

`list_deferred_operations status=pending` → 0. `ai_deferred_operations`: 393 completed, 3 rejected, 1 failed.

**17 pending `ai_approval_requests`** (all `source_type: system_fleet`, all step 1/1 "… Operator Approval"):

| Action category | n | Subject | Expires | Assessment |
|---|---|---|---|---|
| `system.abandoned_instance_reap` | 3 | `sdwan-test-a`, `sdwan-test-b`, `caps-p1-rehearsal-throwaway` (all `stopped` since 10-05, dev plane) | 14:34–14:35Z today, then re-mint | **Destructive (provider terminate).** Legitimate reap candidates if the operator confirms the VMs are disposable. `requires_human_session: true`. |
| `dev.campaign_propose` | 5 | 5 governance gaps (§9) | 14:34Z | code/seed work, not an operator click |
| `system.cert_rotate` | 2 | the hub instance and the reaped dev-cell instance | 14:34Z | **stale** — both subjects already have valid certs or no longer exist (§7); exempt from the unattended-expiry backoff (`fleet_autonomy_service.rb:657`), so it re-mints every 4 h forever |
| `system.sdwan_peer_remediate` | 2 | the two stopped `dryrun-fabric` peers | 14:34Z | stale test fabric |
| `system.sdwan_failover` | 1 | `dryrun-fabric` hub unreachable, 0 candidates | 14:34Z | cannot succeed (`candidate_count: 0`, "operator must promote a peer") |
| `system.module_assign` | 1 | module drift on the stopped `caps-p1` VM | 14:34Z | stale |
| `system.instance_reprovision` | 1 | today's fresh CI builder flagged "silent" at 13:32Z | 17:32Z | **false positive** — the builder heartbeats fine now (minted during its first-boot window) |
| `system.node_lkg_investigate` | 1 | account-level `node_lkg_unarmed` standing 369 ticks | 17:33Z | design noise (§9) |
| `system.module_promotion_investigate` | 1 | `promotion_stalled` for the hub-backend module, created 2026-09-21, **no expiry** | never | the only truly standing request; review |

Historical: 8,924 rejected (expired) requests since 2026-07-19 (first `019f77c5-d147…`, `019f7b1e-bfe1…`,
`019f77d1-b824…`; last `01a1539c-785c…` today). Last 14 days by category: `instance_reprovision` 77,
`dev.campaign_propose` 75, `module_promote_to_live` 30, `sdwan_peer_remediate` 28, `module_assign` 23,
`cloud_sync_check_stale_investigate` 15, `template_closure_apply` 15, `sdwan_failover` 14, `cert_rotate` 13,
`node_boot_image_drift` 10. The `instance_reprovision` and `template_closure_apply` ones are the stub row (§8).

Options → §17 items F, G.

---

## 7. Certificates and expiry

- The hub's **TLS** cert (self-signed, CN = `<ops-hub-host>`, single SAN) is valid 2026-07-17 → **2028-10-19**;
  served identically on 443 for both hub DNS names, hence the name-mismatch on the second name
  (`[fresh-install #15]`). No ACME certificates exist (`system_acme_certificates` = 0).
- **Node (mTLS) certificates** (`system_node_certificates`, 28 rows): every live instance holds a valid cert
  (hub: `01a0d92b-130b…`, issued 2026-09-25, expires 2026-12-24; today's CI builder: expires 2027-01-17).
- The `CertificateExpirySensor` alerts (828 events/day, 3 standing fingerprints, 2 pending `cert_rotate`) are on:

| Cert row | Instance | not_after | State |
|---|---|---|---|
| `019f7c37-475b-765f-be8b-03aaaa22d729` | hub (running) | 2026-10-13 | expired, **superseded** by `01a0d92b…`, `revoked_at` NULL |
| `019f7cca-fc73-718b-b38e-5ebc2b9e6090` | hub (running) | 2026-10-17 | expired, superseded, `revoked_at` NULL |
| `019f7765-543f-720f-b30e-4e99eb804491` | reaped dev-cell (terminated) | 2026-10-16 | expired, instance gone, `revoked_at` NULL |

Root cause: `extensions/system/server/app/services/system/fleet/sensors/certificate_expiry_sensor.rb:21-23`
filters only `revoked_at IS NULL AND not_after < now + window`; it does not skip certs superseded by a newer cert
on the same instance, nor certs whose instance is `terminated`. Also 17 unrevoked certs belong to terminated
instances (1 expired, 16 still "valid" until Oct–Jan) and will each alert when they approach expiry.

Options → §17 item H.

---

## 8. Instances: silent, stale, the stub row, CI builders and pools

| Instance (name prefix) | Plane | Status | Last heartbeat | Assessment |
|---|---|---|---|---|
| `ops-hub-instance-…-052f` | ops | running | fresh (14:10Z) | the control plane itself |
| `ci-native-builders-amd64-pool-…-6e8d` | ci | running | fresh | today's pool member (ready 1/1) |
| `dev-cell-instance-i4m3` | dev | **pending** | never | **stub**: created 09:44:47Z today, no provider region/type/connection columns (they sit only in `config`), no audit row for its creation. Node = the reaped `dev-cell` node. Fires `TemplateClosureDriftSensor` every tick (239 ticks today) → `template_closure_apply` approvals (15 expired in 14 d). |
| `ci-…-1789235824-0-…-09df` | ci | **rebooting** since 2026-09-12 | never | stuck lifecycle; provider said `running` on 09-19 |
| `ci-…-1787273614-0-…-23da` | ci | stopped since 08-21 | 08-21 | pool `draining`; **38,250 ticks** of `module_drift`; 26 auto `module_assign` decisions/day, each refused "plan disruption exceeds auto-apply budget" |
| `ci-…-1789353788-0-…-dbbb`, `ci-…-1791228305-0-…-7d37` | ci | stopped since 10-05 | 10-05 | pool `draining` |
| `sdwan-test-a`, `sdwan-test-b` | dev | stopped since 10-05 | 10-05 | `dryrun-fabric` peers; drive `sdwan_peer_drift` 552/day + `sdwan_hub_unreachable` 276/day |
| `caps-p1-rehearsal-throwaway-20260925` | dev | stopped since 10-05 | 10-05 | "throwaway" by name; drives `instance_abandoned` + `module_drift` |
| 22 terminated rows | dev/ci | terminated | — | 13 CI builders + 9 dry-run ops-cells / the dev-cell; 71 `mark_terminated` audit rows in 7 days (13 at 09:40–09:44Z today = pool recycle after boot) |

`system_get_silent_instances` reports 30 "silent" rows because it includes terminated and never-enrolled rows;
the two running instances heartbeat every minute. The `fleet_instances` degraded verdict is driven entirely by
the stale rows above.

**CI pool** `ci-native-builders-amd64` (dev plane, ephemeral): target 1, ready 1, 0 deficit, last replenished
13:31Z today. 11 `ci-native-builders-…` node rows accumulate (one per builder; see
`docs/operations/ci-builder-record-accumulation.md`). CI runner leases: 646, all released. The
`BootLkgArmSensor` fingerprint is keyed on the **account** (`boot_lkg_arm_sensor.rb:117`
`"node_lkg_unarmed:#{account.id}"`), and each fresh builder is "unreported" for its first minutes, so the
condition has stood since 2026-09-06 (369 ticks, 53 escalations, 619 "acted automatically" notifications).

Options → §17 items G, I, J.

---

## 9. Autonomy and sensor health

Kill switch: not halted. Fleet tick: healthy (1/min). Decision gates in the last 24 h: `decision.pending` 542,
`decision.deduped` 80, `decision.proceed` 74, `decision.awaiting_operator` 150, `autonomy.notified` 65.

Remediation effectiveness: `system_fleet_remediation_outcomes` = `module_assign` 5,317 ineffective vs 3,340
effective; `dev.campaign_propose` 20 ineffective / 1 effective; `instance_reboot` 19 effective;
`abandoned_instance_reap` 4 effective (one of them the dev-cell). 200 fingerprints are past the stuck streak.

Signal states: 2,774 rows, only 57 seen in the last 24 h; 2,678 not seen for 7+ days (aging is absent).

**Standing / noisy sensors (events in the last 24 h, i.e. in ~5 h of uptime):**

| Sensor → signal | Events/24 h | Fingerprints | Subject | Why it re-fires | Fix class |
|---|---|---|---|---|---|
| ModulePromotionSensor → `module_promotion_ready` | 2,440 | 10 | 10 modules "ready to promote" into the `prod` plane (base-os, postgres-primary, system-base, qemu-guest-agent, runtime-ruby, hub-backend, …), `running_count 1`, `required_count 1` | emits every tick while a promotion candidate exists (`module_promotion_sensor.rb:80`); `module_promote_to_live` approvals expire (30 in 14 d) | decision: promote or stop pinning `prod` |
| GovernanceGapSensor → `governance_gap` | 1,380 | 5 | `binding_agent_unknown: platform-health-monitor` (skill_bindings.rb), `executor_without_skill_row: system-reap-orphan-pool-guest` (system_skills_seed.rb), 3 × `tool_family_unregistered: platform-architect:{generate_self_challenge,get_challenge_result,list_challenges}` (ai_engineering_agents_seed.rb) | seeds on the hub are behind the code; `dev.campaign_propose` remediation "ineffective" ×4 → stuck | **code/seed** — also the root cause of §4 |
| CertificateExpirySensor → `cert_expiring` | 834 | 3 | superseded / terminated certs (§7) | no superseded/terminated filter (`certificate_expiry_sensor.rb:21-23`) | data now, code later |
| AbandonedInstanceSensor → `instance_abandoned` | 834 | 3 | the 3 stopped dev VMs | by design (`requires_approval: true`, reason `stopped`); re-decides every TTL | decision |
| ModuleDriftSensor → `module_drift` | 560 | 2 (+2 transient) | stopped builder `…-23da` (38,250 ticks) and `caps-p1` | sensor excludes only `terminated` (`module_drift_sensor.rb:73`); decision engine proceeds, dispatcher refuses on disruption budget — every tick | data now (reap), code later (skip stopped) |
| SdwanPeerDriftSensor / SdwanReachabilitySensor → `sdwan_peer_drift`, `sdwan_hub_unreachable` | 556 + 276 | 3 | `dryrun-fabric` (1 hub, 1 spoke, both stopped since 10-05) | test fabric left behind | data (delete network after reaping peers) |
| BootImageDriftSensor → `boot_image_drift` | 278 | 1 | **the hub itself**: booted disk-image sha ≠ promoted sha | real but standing since 09-06 (9,979 ticks); `node_boot_image_drift` approvals expire (10 in 14 d) | decision (reboot the control plane into the promoted image, or re-promote the booted sha) |
| TemplateClosureDriftSensor → `template_closure_drift` | 261 | 1 | the stub row (§8) | sensor includes `pending` in live statuses (`template_closure_drift_sensor.rb:30-35`) | data (remove stub) |
| CloudSyncCheckStale → `cloud_sync_check_stale` | 141 | 3 | provider regions `<pve-host>`, `<pve-b-host>`, `local` — standing since 09-20 (336 ticks, 5 escalations) | hourly cloud sync does run (power states refreshed 13:17Z today); why the check reads stale was not determined | investigate |
| BootLkgArmSensor → `node_lkg_unarmed` | 3 (+1 standing escalation) | 1 | account-level fingerprint (§8) | ephemeral builders are always briefly "unreported" | code |
| ConfigDriftSensor → `config_drift` | 8 | 8 today (1,752 states lifetime; 14.4 M events lifetime) | module-assignment config drift, auto-fixed by `module_assign` (notify_and_proceed) | today's volume is low; the August storm is history. The per-action "Fleet acted automatically" notification is the residual noise | config (gate to `auto_approve` without notify) / code |
| `sdwan_credential_expiring` → auto refresh | 12 | 14 | works as designed | — | — |

Re-mint mechanics: decision TTL is 1 h (4 h for advancement actions) (`fleet_autonomy_service.rb:1034`);
`ai_approval_expiry` marks expired requests `rejected`; the next tick re-decides. An unattended-expiry backoff
exists (24 h base → 7 d max, `fleet_autonomy_service.rb:645-650`) but `cert_rotate`, `cert_revoke`,
`instance_terminate` and anything `critical` are exempt (`:657`) — which is exactly why the `cert_rotate` and
`sdwan_*` (critical) requests re-mint every few hours. Improvement `01a0fd18` already tracks this.

---

## 10. Noise cleanup plan (for operator approval)

Principle: **stop the source first, then clean once.** Everything in 10.1 is a data/configuration action on the
hub today; 10.2 needs code or seed changes. Bulk operations list count, first 3 and last 1 ids per CLAUDE.md.
Root access ("QGA") means `qm guest exec <hub-vmid>` from `<pve-host>`; "MCP" means an `mcp__powernode__platform_*`
verb from an operator session; "psql write" means the `powernode` role over TCP from the hub shell (technically
possible without root, but a write — treat as break-glass-class and run only on explicit approval, inside a
transaction, with the SELECT shown first).

### 10.1 Fixable by data / configuration on the hub today

| # | Source (volume) | Stop the source | Then clean up | Tool / command | Root? |
|---|---|---|---|---|---|
| S1 | Stub `dev-cell-instance-i4m3` (`01a1538c-9f60-7f4a-aa07-3275f604ae2b`): 261 `template_closure_drift` events/day, `template_closure_apply` + `instance_reprovision` approvals | Mark the row terminated (no provider resource exists, so `system_terminate_instance` would try a provider call with empty ids — prefer the DB path), **1 row** | optionally `system_delete_node` on the `dev-cell` node `019f7758-850e-7b0c-8e0b-a0d07b6090e9` once its terminated instance history is no longer wanted | psql write: `UPDATE system_node_instances SET status='terminated' WHERE id='01a1538c-9f60-7f4a-aa07-3275f604ae2b' AND status='pending';` | no (write) |
| S2 | 3 stale `cert_expiring` fingerprints (834 events/day, 2 `cert_rotate` approvals re-minted every 4 h) | Revoke-mark the 3 superseded/orphaned rows, **3 rows**: `019f7765-543f-720f-b30e-4e99eb804491`, `019f7c37-475b-765f-be8b-03aaaa22d729`, `019f7cca-fc73-718b-b38e-5ebc2b9e6090` | then the 17 unrevoked certs on terminated instances, **17 rows** (first `019f7765-543f…`, `019facf1-9810…`, `019fe4b5-7d3b…`; last `01a15380-98a8…`) | psql write: `UPDATE system_node_certificates SET revoked_at=now(), revocation_reason='superseded_or_instance_terminated' WHERE id IN (...)`. No MCP verb covers node certs (`system_acme_revoke_certificate` is ACME-only). | no (write) |
| S3 | 3 stopped dev VMs (`sdwan-test-a` `01a020f4-3eb6…`, `sdwan-test-b` `01a020f4-b506…`, `caps-p1-rehearsal` `01a0da09-2e5f…`): 834 `instance_abandoned` + ~560 `module_drift` events/day, 3 reap approvals, 2 `sdwan_peer_remediate` | **Operator decision.** If disposable: approve the 3 pending `system.abandoned_instance_reap` requests in the UI (`/app/notifications` → Review) — destructive, provider terminate, 3 VMs on `<pve-host>`. If not: `system_instance_hold` them so the lane stops asking. | then `system_sdwan_delete_network` on `dryrun-fabric` (`019fe651-b757-7dc0-9efd-5932bda8c8d3`) — stops `sdwan_peer_drift` 556/day + `sdwan_hub_unreachable` 276/day + `sdwan_failover` approvals | UI approve ×3; MCP `system_sdwan_delete_network {network_id}` (may require approval) | no |
| S4 | 3 stopped/draining CI builders (`…-23da` `01a021cf-13ea…` since 08-21 with 38,250 drift ticks; `…-dbbb` `01a09dcc-05d1…`; `…-7d37` `01a10d86-dedc…`) and 1 "rebooting" since 09-12 (`…-09df` `01a096c4-0818…`): 26 refused `module_assign` dispatches/day, 4 `held`/`progressing` component rows | Terminate the 4 pool leftovers, **4 instances** (first 3 `01a021cf-13ea…`, `01a096c4-0818…`, `01a09dcc-05d1…`; last `01a10d86-dedc…`). Check provider power state first (`system_instance_hold_status`), C9: these are ephemeral pool members, no persistent data. | pool keeps target 1 | MCP `system_terminate_instance {instance_id}` ×4 (may require approval) | no |
| S5 | `module_promotion_ready` ×10 (2,440 events/day) and 30 expired `module_promote_to_live` approvals | **Operator decision**: (a) promote the 10 versions into `prod` (`system_promote_module_version {environment:"prod", module_id}` ×10, each gated), or (b) if no prod nodes exist yet, set the `prod` plane to follow publishes (`environment_update {environment:"prod", auto_promote_on_publish:true}`) so the sensor has no pinned rung to compare | — | MCP | no |
| S6 | Hub `boot_image_drift` (278 events/day, 10 expired `node_boot_image_drift` approvals) | **Operator decision, C9-sensitive**: `system_upgrade_boot_image {instance_id: <hub instance>}` reboots the **control plane** into the promoted UKI — schedule it, snapshot first; alternative: re-promote the currently booted disk image so promoted == booted | — | MCP (destructive) | no (but plan downtime) |
| S7 | `Sidekiq is down` / `Redis|Postgres is degraded` alerts (121+121+1) and the false core-service verdict | Set `SIDEKIQ_REDIS_URL=redis://127.0.0.1:6379/0` in the Rails unit environment (`/persist/powernode-rails/backend-default.conf`), restart the rails unit; verify `probe_sidekiq` → `process_count 1`. Also drain the one stranded job in DB 1 (`redis-cli -n 1 lrange queue:system 0 -1` to see its class, then decide to re-enqueue or `DEL`). | — | **QGA** (root-only file + unit restart); the module-config path is a hub-backend manifest/env change + redeploy | yes |
| S8 | 20,868 stale unread notifications | After S1–S7 (so the sources stop re-creating them): dismiss. There is no per-type bulk verb; `dismiss_all_notifications` is **all** active notifications for the user — it would also take the 25 `[fresh-install]` proposals and 17 live approval cards. Options: (a) mark the 25+17 as handled first, then `dismiss_all_notifications`; (b) psql write by type. Counts and ids: **8,946** approval_required with non-pending request (first `019f77bf-6852-7666-b6cf-e3856f0067c7`, `019f77c5-d14b-7cbe-8c9a-a680800093e0`, `019f77cb-4fae-7e85-b7c2-0b72e418a8a0`; last `01a1539c-7a29-773b-908d-4962ca5f887b`); **4,976** system_alert created before 2026-10-19 14:04Z (first `01a09708-ae25…`, `01a09716-6468…`, `01a09750-d351…`; last `01a1545e-b664…`); **5,776** agent_status_update (first `01a0744d-1742…`, `01a0744d-17c1…`, `01a0744d-18be…`; last `01a1547b-da5f…`); **1,157** agent_escalation (first `01a0748f-e67c…`, `01a074c3-3129…`, `01a07526-0aed…`; last `01a1545d-9eb6…`); **13** ai_plan_review. | — | MCP `mark_all_notifications_read` / `dismiss_all_notifications` (no filter) or psql write `UPDATE notifications SET dismissed_at=now(), read_at=now() WHERE notification_type=... AND ...` | no |
| S9 | 39 open governance reports (30 resource_abuse / 5 policy_violation / 4 anomaly, 6-hourly from 09-17 to 09-30; subjects Platform Developer, Release Manager, SDWAN Manager, Platform Architect) | Source already stopped (last report 09-30; `AiGovernanceScanJob` has 2 dead entries, 09-30 is the last day it produced anything — verify it is still scheduled: it is in `schedules`). Resolve the 39 as `dismissed` with a note "duplicate of standing condition; dedupe pending", **39 rows** (first `01a0b086-885d-7f6f-bcf9-f00babfd4854`, `01a0b1d0-1e3a-7e89-aa2f-40ae73d394b5`, `01a0b1d0-1fad-781e-b24a-737dcf04aa1b`; last `01a0f22f-9ce5-7b9a-aa03-99e66358976f`). | — | MCP `resolve_governance_report {report_id, resolution_status:"dismissed", notes}` ×39 | no |
| S10 | 8,924 expired approval requests (`rejected`) and 2,678 stale signal states | Archive/prune (C8). No MCP verb; `archive_by_predicate` / `hard_delete_archived` exist for other models — check whether they accept `Ai::ApprovalRequest`. Otherwise psql delete in batches after a dump. | — | MCP or psql write | no |
| S11 | Fleet-event volume (§12) | `POWERNODE_FLEET_EVENT_RETENTION_DAYS=30` on the Rails unit env (the sweep reads it server-side: `worker_api/fleet_controller.rb:61-62`), restart rails; next 04:30Z sweep deletes routine rows older than 30 d (high/critical kept 365 d) | VACUUM afterwards (§12) | **QGA** | yes |
| S12 | Dead set 5,378 | Nothing to retry (all outage residue or 404s); clear via Sidekiq Web "Dead → Delete all" or `redis-cli -n 0 DEL dead` (Redis is unauthenticated on localhost, so pnadmin **can** write it — treat as an operator action) | — | Sidekiq UI / redis-cli | no |

Expected effect of S1–S6 on event volume: removes ≈5,300 of today's ≈9,990 events (projected ≈17k/day →
≈6k/day), 13 of the 17 pending approvals stop re-minting, and `fleet_remediation` leaves `RemediationStuck`.

### 10.2 Needs a code or seed change (file the ones not already filed as proposals)

| # | Item | Where | Overlaps |
|---|---|---|---|
| K1 | Seed/restore the `platform-health-monitor` global agent and the `system-reap-orphan-pool-guest` skill row; register the Platform Architect `tool_families` | `extensions/system/server/app/services/system/ai/skills/skill_bindings.rb`, `extensions/system/server/db/seeds/system_skills_seed.rb`, `server/db/seeds/ai_engineering_agents_seed.rb`; applying needs `rails db:seed` on the hub (QGA) or a deploy | GovernanceGapSensor's own 5 proposals (`dev.campaign_propose`), the stuck remediation |
| K2 | `CertificateExpirySensor`: skip certs superseded by a newer unexpired cert on the same instance; skip `terminated` instances; auto-revoke-mark on supersede | `certificate_expiry_sensor.rb:21-23` | new |
| K3 | `ModuleDriftSensor` / `module_assign` lane: do not assess `stopped`/`draining` pool members, or stop deciding when the dispatcher will refuse on disruption budget | `module_drift_sensor.rb:73`, decision engine | C9 |
| K4 | `BootLkgArmSensor`: key the fingerprint per node, exclude ephemeral pool members younger than N minutes | `boot_lkg_arm_sensor.rb:117-128` | new |
| K5 | `TemplateClosureDriftSensor`: exclude `pending` rows with no provider binding | `template_closure_drift_sensor.rb:30-35` | new |
| K6 | Governance `MonitorService`: dedupe open reports by (subject_agent, report_type) instead of creating one per 6 h run | `server/app/services/ai/governance/monitor_service.rb:24-30, 214` | new (C8) |
| K7 | Approval re-mint cadence; resolve the old `autonomy_approval_required` notification when its request expires; include `cert_rotate` in the unattended backoff | `fleet_autonomy_service.rb:645-668, 1034` | improvement `01a0fd18` (pending) |
| K8 | `Platform::Status::Escalation`: cap re-notifications per row (e.g. 1/day after the first) | `server/app/services/platform/status/escalation.rb:67-68` | C8 |
| K9 | Signal-state aging (delete rows unseen for N days) and approval-request archival | new job | C8 |
| K10 | Reaper hardening: provider `running` ⇒ approval; suppress while the hub's own instance is silent; dev-cell/persistent-home templates always approve; snapshot before terminate | `abandoned_instance_sensor.rb:114-138, 231` | **`[fresh-install #16]`**, C9 |
| K11 | Server/worker Redis DB default alignment (make the server default to the worker's actual DB, or fail the probe loudly) | `server/config/initializers/redis.rb:122-128` | new |
| K12 | `database_backups` left `pending`: make the worker mark `failed` with the error, and surface it as a component | `worker/app/jobs/maintenance/database_backup_job.rb` | new, **P1** |
| K13 | `/.well-known` routing, TLS SAN, schema.rb lag, MCP session agents | — | `[fresh-install #14, #15, #7, #25]` |

---

## 11. Resource headroom

| Resource | Value | Assessment |
|---|---|---|
| CPU | 8 vCPU, load 0.18–2.4 | fine |
| Memory | 15 GiB, 2.9 GiB used, 12 GiB available, **no swap**; puma RSS 1.6 GB, sidekiq 0.3 GB | fine; no swap means an OOM is fatal rather than slow — relevant to §2 |
| `/` (overlay) | 512 MB, 23 % used | ephemeral root; anything writing under `/var` (e.g. `BACKUP_DIR=/var/backups/powernode`) lands here |
| `/persist` | 150 GB, **113 GB used (79 %)**, 31 GB free | 45 GB `powernode-oci-cache` (module images, 125+ `.cfs` of ~350 MB), 30 GB `cache/modules`, ~23 GB Postgres, 9.1 GB `powernode-file-storage/disk_image`, 2.9 GB `backups` (the single dump) |
| Redis | 9 MB of 4 GB | fine |
| Postgres | 24.2 GB, 30-connection pool (3 busy), 10 connections | fine; `system_fleet_events` 20 GB is 83 % of it |
| `/run/powernode/modules` | 12 module images mounted | — |

Risk: a 30-day fleet-event retention plus `VACUUM FULL` needs a full table copy (~13 GB heap) — there is room
for it today but not after much more growth. `pg_repack` or accepting space reuse (plain VACUUM) avoids the copy.
The two caches (75 GB) are the real headroom lever: check `system_set_disk_image_retention` and the module cache
retention before the DB.

---

## 12. Data hygiene

| Table / store | Rows / size | Growth | Retention mechanism | State |
|---|---|---|---|---|
| `system_fleet_events` | 32.0 M / 20 GB (heap 13 GB; indexes: account+emitted_at 1.2 GB, pkey 963 MB, payload GIN 732 MB, emitted_at 686 MB, 6 more ~215 MB each) | Jul 6.6 M, **Aug 23.4 M** (the `config_drift` 14.4 M + `decision.deduped` 13.0 M storm), Sep 1.7 M, Oct 0.33 M; now ≈47k/day up to 10-05, ≈17k/day pace today (≈11 MB/day at 656 B/row) | nightly 04:30Z `SystemFleetEventRetentionJob` → `POWERNODE_FLEET_EVENT_RETENTION_DAYS` (default 90; critical/high 365) | oldest row 2026-07-18 = 93 d, consistent with a 90-day sweep that ran while the hub was up. **31,180,951 rows older than 30 d** (critical 307,524 · high 1,629,703 · medium 28,859,760 · low 384,215); first `019f73fc-b8e1…`, `019f73fc-b904…`, `019f73fc-b8b8…` (07-18 `module_publish_failed`); last `01a0b72d-c530…` (09-19 `module_drift`). |
| Sidekiq dead set | 5,378 | +56 today (404s) | Sidekiq default (6 months / 10k) | clear (S12) |
| `notifications` | 20,919 / 14 MB | ~140–620/day when up | none found in code | S8 + K8 |
| `ai_approval_requests` | 8,971 / 18 MB (118 dead tuples) | ~28–86/day | expiry marks `rejected`; no archival | S10 + K9 |
| `system_fleet_signal_states` | 2,774 | — | none | 2,678 unseen 7 d+ (first `01a07816-9ff2…`, `01a07658-bc6b…`, `01a07812-04f9…`; last `01a11f08-9fe9…`) |
| `ai_governance_reports` | 39 open | stopped 09-30 | none | S9 + K6 |
| `system_node_instances` / `system_nodes` | 32 / 31 | +1–3 builders/day | none (see `ci-builder-record-accumulation.md`) | 22 terminated instances (first `019f7758-85a9…` dev-cell, `019facd9-4339…`, `019fe4b5-2e0a…`; last `01a1537f-c79a…`); the 6 `docker_host` component rows (`NeverSynced`) belong to 08-09 dry-run cells and will clear when their `devops_docker_hosts` rows are removed |
| `system_node_certificates` | 28 | 1/builder | none | S2 |
| `ai_knowledge_graph_nodes` 1.9 GB, `audit_logs` 295 MB, `ai_shared_knowledges` 177 MB, `ai_stigmergic_signals` 129 MB (552 live / 540 dead tuples) | — | — | — | out of scope (streamlining review), noted for size |
| `pg_stat_user_tables` `last_autovacuum` | NULL for fleet_events/notifications/approval_requests | — | autovacuum | 0 dead tuples on fleet_events, so no bloat yet; the index set (10 indexes) is where the 90→30 day cut pays off |

---

## 13. Backups and DR (new finding, P1)

- `/persist/backups/`: one file, `powernode_production-20260926T002418Z.dump` (3.05 GB, root:root, 2026-09-26
  00:31Z) plus a `builder-cleanup-20260802` directory. Nothing since.
- `database_backups` table: 20 rows, **all `pending`** with `started_at` set and no `completed_at`, `file_path`
  or `error_message` (12 in Sep, 8 in Oct, the last 2026-10-07 02:00Z; a `manual` one 10-04 03:00Z also pending).
  The 02:00Z `daily_database_backup` schedule is loaded; `Maintenance::ScheduledBackupJob` creates the row via
  `/api/v1/internal/maintenance/backups`, then `Maintenance::DatabaseBackupJob` is supposed to run `pg_dump` into
  `BACKUP_DIR` = `ENV['BACKUP_DIR'] || '/var/backups/powernode'` (`worker/app/jobs/maintenance/database_backup_job.rb:15`).
  Neither job is in the dead set, so the failure is swallowed (or the second job is never enqueued). On the hub,
  `/var/backups` is on the 512 MB ephemeral overlay, and the worker image may not ship `pg_dump`.
- Hypervisor-level: knowledge mentions no snapshot/`vzdump` schedule for `<hub-vmid>`; the dev-cell loss showed
  the cost.
- Redis (`/persist/redis`, root-only) holds the Sidekiq schedules/dead set only — not critical.

Options → §17 item B.

---

## 14. External dependencies seen from the hub

| Dependency | Result from the hub | Assessment |
|---|---|---|
| DNS resolver | systemd-resolved → one upstream, search domain `<fleet-domain>` | works; **the hub's own name resolves to a different address than the one recorded in `deployment-ops-hub` knowledge** — verify the DHCP lease/DNS record (fleet nodes reach the hub by that address). Reported with values in the chat summary, not here. |
| Gitea `<gitea-host>` (HTTPS) | resolves; `/api/v1/version` → 403 in 0.49 s | reachable; auth required (expected). The recurring `Git::PipelineSyncJob` 404s mean a repository/pipeline the hub still polls has been removed or renamed on Gitea — check `git_pipelines`/`devops` repo rows. |
| Gitea SSH `<gitea-ssh-host>` | resolves; HTTPS probe times out (8 s) | not an HTTPS endpoint; only relevant for SSH remotes, not probed further |
| Hypervisor API `<pve-host>:8006` | 401 in 3.0 s | reachable (auth required) |
| Vault `<vault-host>` | 503 `sealed: true, standby: true` (1.15.6) | **sealed since 2026-07-29** per knowledge; anything depending on Vault (credential restoration, module signing in `vault` mode) is unavailable. Signing mode is `local`. |
| NAS NFS (`/mnt/pve-data`) | not mounted on the hub | knowledge says snippets live there via the hypervisor; the hub-side mount recorded in knowledge is absent — verify whether `snippets_local_path` is still used |
| Time sync | `System clock synchronized: no`, `NTP service: n/a` | **fix**: no chrony/timesyncd in the composed image; clock drift breaks mTLS validity windows, JWT `exp`, ACME and audit ordering |
| OCI registry | not probed (no registry URL exposed in a readable config); module images present in `/persist/powernode-oci-cache` | — |
| Federation | 0 peers, 0 subscriptions | nothing configured; `FederationHeartbeatJob` still ticks (598 dead entries from outages) |
| SDWAN | 1 network (`dryrun-fabric`), 2 peers both lost since 10-05, 0 VIPs, 0 BGP | test fabric; see S3 |
| LLM providers | OpenAI, Anthropic, Grok credentials active; 0 executions in the last 24 h | not exercised during the review window |

---

## 15. Governance, campaigns, improvements

- Governance dashboard: 39 open reports (all `warning`), 0 critical, 0 collusion indicators, 4 agents "under
  investigation" (Platform Developer ×22 reports, Release Manager ×8, SDWAN Manager ×4, Platform Architect ×5).
  Evidence is `{"type":"excessive_resource_usage"}` with no numbers — `monitor_service.rb:157 resource_abuse?`
  re-fires every 6 h with no dedupe (K6). No report has been created since 2026-09-30 12:00Z.
- Campaigns: 7 `active` with 0/… tasks completed since 2026-09-19 (LLM symbol summaries, ScratchSize, session
  observations, context ledger, core-purity burn-down, render-helper args, MCP runner) — no driver lease, no
  activity for a month; 13 completed.
- Improvements: ~50 pending offers (housekeeping 1–12/12 for `wt.sh`, security/disclosure follow-ups, the
  approval re-mint cadence, int4 overflow, GDPR export path, …). Not triaged here (streamlining review).
- Audit log: 221 rows since 10-15 (last 7 d: 126 `updated` GitRunner last_seen, 71 `mark_terminated`, 13 agents
  `created` — the `<client> #N` MCP session agents, `[fresh-install #25]`), 3 logins today, 0 high/critical risk.

---

## 16. Risky automations and safety posture

| Lane / control | State | Risk |
|---|---|---|
| **INV-1 `self_hosting_node_id`** | **SET** to the ops-hub node id on 2026-09-07 21:33Z (verified in `site_settings`) | The knowledge entry "INV-1 is UNARMED" (2026-09-07 00:15Z) predates the write and is stale — update it. `SelfManagementFence` should now refuse stop/reboot/terminate/provision against the hub's node. Not exercised here (that would be a write). |
| `system.abandoned_instance_reap` | `auto_approve` when `approval_reasons` is empty, i.e. for `starting`/`error` guests holding no volume/VIP (`abandoned_instance_sensor.rb:114-138`); `max_per_tick 10`, `abandon_after_seconds 604800` | **Still the lane that destroyed the dev-cell.** Any guest the platform marks `error` during a hub outage (and the hub has been out ~10 of 14 days) is reaped on the first tick after 7 silent days. Today's 3 candidates are `stopped` so they ask; a guest that flips to `error` would not. Interim mitigation without code: set `abandon_after_seconds` higher (e.g. 30 d) via `system_update_sensor_config {sensor:"abandoned_instance", config:{abandon_after_seconds:2592000}}` (no root, reversible) until `[fresh-install #16]` lands. |
| `system.module_assign` `notify_and_proceed` | auto-applies module assignment on drift/config-drift; 80 % disruption plans are refused by the budget | contained by the disruption budget; noisy |
| `system.instance_reboot` | 19 effective reboots recorded (`instance_state_drifted:*:stopped`) | reboots guests the provider reports stopped — fine for pool members; confirm it cannot target the hub (INV-1 covers it if armed) |
| `system.upgrade_boot_image` / `node_boot_image_drift` on the hub | pending-expired ×10 | approving it reboots the control plane — do it deliberately (S6) |
| Publish → auto-promote → live recompose | knowledge incident 2026-09-21 | unchanged; still a C9 item |
| Kill switch | not halted; `emergency_halt` available | note that halting the hub's own autonomy does not stop a provider-level action already dispatched |
| Break-glass | none armed (cannot be verified from pnadmin; QGA exec works per knowledge) | — |
| Unauthenticated local Redis | `redis-cli` from pnadmin can read and write Sidekiq state | acceptable on a single-tenant hub, but it means "read-only shell" is not strictly read-only for Redis |

---

## 17. Remediation options, ranked

Legend: **Root** = needs root via QGA on `<pve-host>`; **Approval** = operator approval in the UI/MCP;
**Code** = change + deploy.

### A. Repeated control-plane outages (now)
1. **Collect evidence (recommended first):** via QGA, `journalctl --list-boots`, `journalctl -b -1 -p warning`,
   `journalctl -u <rails unit> -b -1`, `dmesg -T | grep -i oom`; on `<pve-host>`, `qm status <hub-vmid>`,
   `/var/log/pve/tasks` for stop/start of `<hub-vmid>`, host `journalctl` around 10-06 04:55Z, 10-07 21:37Z,
   10-09 21:43Z, 10-15 07:23Z. Risk: none (reads). Reversible: n/a. **Root.**
2. **Re-arm the external watchdog** (`docs/operations/ops-hub-watchdog.md`, the watchdog VM on `<pve-b-host>`)
   with `TARGET_URL=https://<ops-hub-host>/up`; it should page and optionally `qm start`. Risk: a watchdog that
   restarts the VM can mask the root cause; set it to notify-only until A1 is answered. Reversible: yes. Root on
   the watchdog VM.
3. **Add swap or a memory cap** if A1 shows OOM (15 GiB, no swap, puma at 1.6 GB RSS). Root.

### B. No working backup (now)
1. **Hypervisor snapshot / `vzdump` of `<hub-vmid>` today**, stored on the NAS, before any other change in this
   list. Risk: brief I/O stall. Reversible: delete snapshot. Root on `<pve-host>`. **Recommended.**
2. **Fix the in-platform job:** set `BACKUP_DIR=/persist/backups` (or a NAS mount) in the worker unit env, confirm
   `pg_dump` exists in the worker image, restart the sidekiq unit, trigger one `manual` backup and watch the
   `database_backups` row reach `completed`. Root (unit env). Then K12 so failures are visible. **Recommended.**
3. **Interim manual dump via QGA:** `sudo -u postgres pg_dump -Fc powernode_production > /persist/backups/<ts>.dump`
   and copy off-host. Root. Use until B2 is verified.

### C. Scheduled health sweep silent since 09-19 (now)
1. **Seed the missing canonical** (`platform-health-monitor`) — `rails db:seed` subset on the hub via QGA, or
   deploy the next hub-backend build whose boot seeds it. Verify `system_platform_health_snapshots` grows every
   15 min and the 5 governance gaps clear. Risk: seeding touches agent/skill rows; run the system seeds only.
   Reversible: no (seed), but idempotent. **Root/Code. Recommended.**
2. **Interim:** run `system_platform_health_check` manually once a day (MCP, no root) — it persists a snapshot
   and clears SnapshotStale (see §0.3). Reversible: n/a.
3. Configure `system.platform_health.reverse_proxy_health_url` and `mcp_health_url` site settings so those two
   stop reading `not_measured` (needs the SiteSetting write path — `site_setting_set` MCP verb exists).

### D. Server/worker Redis DB mismatch (now)
1. **`SIDEKIQ_REDIS_URL=redis://127.0.0.1:6379/0`** in the Rails unit env, restart rails (≈30 s `/up` 502).
   Verify `probe_sidekiq.process_count == 1`. Risk: 30 s API outage; blast radius hub only. Reversible: remove the
   line. **Root. Recommended.**
2. Alternatively set the worker's `REDIS_URL` to `/1` — **not recommended**: it abandons the live Sidekiq state
   (schedules, dead set) in DB 0.
3. Drain DB 1 `queue:system` (1 job): re-enqueue the package sync via `system_sync_package_repository` (MCP) and
   `redis-cli -n 1 DEL queue:system queues`. Reversible: n/a. No root.
4. Code: K11.

### E. Clock not synchronized (now)
1. Check the image for `systemd-timesyncd`/chrony and the hypervisor's `kvm-clock`; enable NTP against the
   LAN resolver/gateway. Root. Low risk. **Recommended.**

### F. Pending approval backlog (this week)
1. **Decide once** (S3/S4/S5/S6), then let the 13 re-minting requests stop. Approvals via `/app/notifications`.
2. Reject the `instance_reprovision` for today's builder (false positive) and the `node_lkg_investigate` card;
   they will re-mint until K4 lands — acceptable at 1 card/4 h.
3. Review the 09-21 `module_promotion_investigate` (hub-backend promotion stalled) — the only non-expiring one.

### G. Stale live instances and the stub row (this week)
1. S1 (stub) psql write, 1 row. Reversible (set status back). **Recommended.**
2. S3 (3 dev VMs): approve reap **only after** confirming on `<pve-host>` that the VMIDs hold nothing persistent
   (the dev-cell lesson). Alternative: `system_instance_hold` to silence the lane without destroying anything.
3. S4 (4 pool leftovers): `system_terminate_instance` ×4. Reversible: no (ephemeral). **Recommended.**
4. Then `system_sdwan_delete_network` for `dryrun-fabric`.

### H. Certificates (this week)
1. S2 psql write, 3 rows now, 17 rows next. Reversible (clear `revoked_at`). **Recommended.**
2. Code K2.
3. TLS SAN / single hub name: `[fresh-install #15]`.

### I. Sensor noise (this week)
1. S5 decision on `prod` promotions; S6 hub boot-image decision (schedule a maintenance window, snapshot first).
2. `system_update_sensor_config` is limited to the writable sensors (`abandoned_instance`, `instance_status`,
   `instance_unrecoverable`, `orphan_pool_guest`, `boot_image_staleness`, `governance_gap`, `replica_lag`,
   `terminated_guest_present`); the noisiest ones (promotion, cert, template closure, LKG) are not tunable →
   K2–K5.
3. Investigate `cloud_sync_check_stale` ×3 (regions) — read `System::CloudSync` check-stale logic; not resolved here.

### J. Notifications, governance reports, approvals, signal states (this week)
1. S8 after S1–S7; prefer the psql-by-type path so the 25 proposals and 17 live cards survive; or mark those 42
   as read/handled first and use `dismiss_all_notifications`. **Recommended: psql by type**, 5 statements, counts
   in S8.
2. S9: `resolve_governance_report` ×39 `dismissed`. **Recommended.**
3. S10 archival after a dump (B1).
4. Code K6–K9.

### K. Fleet events and disk (this week)
1. S11: retention 30 d (root env), then plain `VACUUM (VERBOSE) system_fleet_events` (space reused, not returned)
   or `pg_repack` (returns ~15 GB; needs the extension) — avoid `VACUUM FULL` on a 79 % disk. **Recommended.**
2. Cache pruning: review `system_set_disk_image_retention` and the module cache (75 GB) — likely larger win than
   the DB. No root for the MCP verb; the on-disk purge is the agent's.

### L. Reaper hardening (this week, C9)
1. Interim: `system_update_sensor_config {sensor:"abandoned_instance", config:{abandon_after_seconds:2592000}}`
   (30 d) — reversible, no root. **Recommended until #16 lands.**
2. Code: `[fresh-install #16]` (provider running ⇒ approval; hub-silent suppression; snapshot before terminate).
3. Update the stale INV-1 knowledge entry (knowledge write, operator).

### M. Later
- Record hygiene for terminated instances/nodes/docker hosts (`ci-builder-record-accumulation.md`).
- `Git::PipelineSyncJob` 404 target cleanup (remove or re-point the stale pipeline).
- Vault unseal or formally retire the dependency (sealed since 07-29).
- The five MCP read verbs that return `null` (`health`, `alerts`, `provider_health`, `metrics`, `recent_events`).
- 7 stalled campaigns since 09-19: pause or archive.

---

## 18. What could not be inspected

- The journal (`journalctl`), `/persist/redis`, `/persist/var/lib/postgresql` (du), the Rails/worker unit env
  files — root-only. The outage root cause (§2), the backup job's actual error (§13) and the sweep job's logged
  skip reason (§4, inferred from code) therefore rest on indirect evidence.
- Hypervisor state for `<hub-vmid>` (task log, snapshots, backup schedule) — needs `<pve-host>` access.
- Whether the external watchdog VM is running.
- The OCI registry endpoint and module cache retention settings.
- `platform_health`, `alerts`, `provider_health`, `metrics`, `recent_events` MCP verbs returned `null`.
- `recent_signals` returned only the latest 200 events (all from the last ~20 minutes); counts above come from the
  DB instead.

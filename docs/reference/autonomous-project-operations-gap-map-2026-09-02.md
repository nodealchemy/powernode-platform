# Autonomous Project Operations — Gap Map (2026-09-02)

**Goal (operator, 2026-09-02).** Full autonomous capability to provision and manage all
resources a project needs, and to intervene and remediate automatically when necessary
for scaling and disaster recovery.

**Frame.** This extends the 2026-08-12 readiness doc
(`docs/operations/autonomous-infrastructure-readiness-2026-08-12.md`) and the
2026-09-02 extension evaluation (`system-extension-evaluation-2026-09-02.md`). It maps the
goal onto four arms — **provision, sense, scale, recover** — and states for each what runs
today, what is missing, and which existing seam the missing piece extends. Everything is
verified against the tree at `extensions/system@5b2bd6e2`.

---

## 0. Where we are since the August readiness doc

Three of its "genuinely missing" items have moved:

| Arm | August status | Today (evidence) |
|---|---|---|
| Act (adaptation lane) | propose-only, unbuildable in isolation | **Dispatches.** `propose_project_adaptation` → `Ai::Provisioning::AdaptationDispatchService#dispatch!` through the `adaptation_gate` seam with ratified verdicts incl. `auto_apply_within_bounds` (`decision_engine.rb`, `adaptation_dispatch_service.rb:17-92`) |
| Sense (telemetry producers) | 2 live metrics | **4 live**: `replica_count`, `region_count`, `memory_pct` (heartbeat-ingested, `44eaea13`), SDWAN-peer throughput (`project_metrics_collector.rb:143-149,254`). `verify:` manifest probes run on-node and report on the heartbeat (`b4f41c35`, `368de67b`) |
| Scale-in | no removal strategy | `remove_replicas` exists with a blast-radius prefix rail (`scale_project_executor.rb:61,96`) |
| SLO lane | unclear | Ratified **dormant** 2026-08-23 with an absence ratchet (`5f773c24`); the live convention is `ProjectMetric → ProjectSloSensor → DecisionEngine` |

The create arm (module file-spec authoring through Gitea) is unchanged and is not on the
critical path for scaling/DR.

---

## 1. Provision — "all resources a project needs"

**Runs today.** Concierge NL → approval-gated `Ai::Mission` → `ProvisionFullStackExecutor`
(compute + SDWAN enrol + per-instance volumes + service exposure), with `operation_id`
idempotency and a blast-radius name prefix. Instance pools supply warm capacity.

**Missing for the goal**

| Gap | Evidence | Seam to extend |
|---|---|---|
| Three of four public clouds inert: AWS/GCP/OpenStack SDK gems never bundled; registry advertises them | `providers/registry.rb:13-17`; gemspec "task 3" | Add gems, or make `available_providers` exclude adapters whose client constant is undefined |
| Credential lifecycle is human-only: provider credentials, storage credential rotate, CI token rotate have no MCP verb | parity audit §7 of the evaluation | Wrap the REST actions; rotation itself stays operator-gated per §7 of the readiness doc |
| Project data has no backup path. `ScheduledBackupJob`/`DatabaseRestoreJob` back up the **platform's** DB only; volume snapshot is REST-only (`provider_volumes#snapshot`), no MCP verb, no schedule | `worker/app/jobs/maintenance/scheduled_backup_job.rb:55`; `provider_volumes_controller.rb:95` | `system_snapshot_volume` MCP verb + a per-project snapshot policy the tick loop enforces |
| Workload plane is invisible to sensors: nothing watches `ProvisioningCodeDeployment` or `DockerHost` after `running` | readiness doc §3 (still true: no sensor greps those names) | New `WorkloadHealthSensor` over the existing verify-probe channel |

---

## 2. Sense — what autonomy can see

**Live signals:** heartbeat presence (silent-instance), provider state drift, module/config/
template/storage drift, memory_pct, replica/region counts, SDWAN throughput, verify-probe
results, cert expiry, CVE exposure, GitOps drift, boot/LKG telemetry.

**Missing for scaling and DR**

| Gap | Why it blocks the goal | Seam |
|---|---|---|
| No CPU, latency, availability or error-rate producer. `memory_pct` is the only load signal | Scaling on memory alone over- or under-provisions CPU-bound and I/O-bound projects | Heartbeat already carries a runtime-metrics block (`status_controller.rb:206`); add cpu/load; add an availability probe via `verify:` |
| No **instance-down** signal distinct from **instance-silent**. Silent → reboot self-heal; a dead VM, dead host, or dead region produces the same signal and the same reboot | DR needs "replace", not "reboot" | Extend `SilentInstanceSensor` with provider-state + consecutive-failure escalation to a new `instance_unrecoverable` kind |
| No cost producer behind `project_cost_breach` (lane exists, proposal-only) | "Within constraints" has no live cost input | Provider pricing catalog exists (`ProviderInstanceType`); a nightly cost sampler into `ProjectMetric` |
| Notify lanes end in `Rails.logger` | Operators do not see what autonomy declined to do | Route `notify_and_proceed` to `FleetEvent` + ApprovalRequest inbox |

---

## 3. Scale — intervene automatically

**Runs today.** `ProjectSloSensor` → `system.project_slo_violation` → adaptation plan →
`adaptation_gate` → `ScaleProjectExecutor` (`add_replicas`, `add_region`,
`vertical_resize`, `remove_replicas`) → post-adapt verification.

**Missing**

| Gap | Evidence | Seam |
|---|---|---|
| Platform self-scaling is a decoy: `platform_resilience scale` writes `target_replicas` and says "provisioning sync to create/drain instances is queued for a follow-up slice" | `platform_resilience_executor.rb:215` | Either wire `PlatformDeploymentOrchestrator` to reconcile `target_replicas`, or remove the verb. §7 says the control plane must not self-remediate, so the honest choice is: reconcile only for **non-hub** `PlatformDeployment`s |
| `drain_instance` in the same executor writes markers nothing reads: "Nothing was stopped or cordoned" | `platform_resilience_executor.rb:137-142` | A real drain = cordon in K3s/Docker + VIP move + pool return; all three verbs exist separately |
| Bounds for `auto_apply_within_bounds` must be DB-driven per project (min/max replicas, budget, regions) | memory: no hardcoded budgets | `InstancePool` already has `min_size/max_size`; project-level bounds belong on the mission configuration |
| Only one load metric feeds the SLO sensor | §2 | Same fix as §2 |

---

## 4. Recover — disaster recovery

**Runs today (verified):** silent-instance reboot with AASM-legal action choice; provider-
state convergence; SDWAN VIP failover (`sdwan_vip_failover_executor`, no-op on a single-
server cluster by design); boot A/B slot + LKG rollback; `system_revert_disk_image`;
`system_rollback_module_version`; storage migration plan→approve→sync→cutover→revert;
`add_region` (parallel stack in a new region); platform-DB backup + restore; Proxmox
snapshots (REST only); federation v1 (built, zero live peers).

**Missing — this is the largest gap**

| Gap | Evidence | Seam |
|---|---|---|
| **No replace-instance lane.** Nothing composes "instance unrecoverable → acquire pooled instance → reattach volumes → re-enrol SDWAN → move VIP → mark old for reap" | no executor references both `acquire_pooled_instance` and `attach_volume`; DR runbooks are manual | New `ReplaceInstanceExecutor` composing five existing verbs, gated `auto_apply_within_bounds` for the additive half, approval for the reap |
| **No database failover.** `postgres-replica` streams from a primary; no promote path exists anywhere (grep `promote`/`pg_promote` across module manifests, orchestrator, worker job: none) | `modules/postgres-replica/manifest.yaml`; `cluster_member_pg_replica_setup_job.rb` | `PromoteReplicaExecutor` (agent task `pg_ctl promote` + VIP repoint + rewire `DATABASE_URL` upstreams to the overlay VIP per the component-per-instance north star) |
| **No project data backup/restore** (see §1) | — | Snapshot verb + schedule + `RestoreVolumeExecutor` |
| **VIP failover needs a multi-server cluster**; the fabric has **zero enrolled peers** in production today | memory: SDWAN data plane has no live deployment | Data-plane campaign (already open) is a hard prerequisite for any network-level DR |
| **Cross-region failover** touches DNS repoint, which §7 ratifies as never-automated | readiness doc §7 | Keep DNS gated; automate everything up to it (region stack up, VIP live, health green), then page for the repoint |
| **Control-plane DR** is explicitly out of autonomy's scope (self-detach precedent) | readiness §7; memory `ops-hub-self-detach-outage-cve-storm` | RCP v2 (second control plane) is the answer, not a lane |
| Cert rotation is advertised as automatic and does nothing | evaluation L1/L2 | Implement `NodeCertificate#rotate` + applier, or de-advertise |

---

## 5. Structural prerequisite: gating must be uniform before "automatic" is safe

The goal says *automatically*. Today automation is trustworthy only inside the 60 s tick
loop, because that is the only path that consults intervention policy:

- One of 269 MCP actions declares `mutating: true`; node delete, instance destroy, module
  promote/rollback and platform deploy run ungated from MCP.
- No skill executor is gated when invoked directly; `requires_approval` on 17 descriptors is
  "DESCRIPTIVE ONLY" by the code's own comment.
- Four proceed lanes actuate nothing and mint false stuck-remediation alarms.

Until every write path meets the same gate, "auto within bounds" is a property of one loop,
not of the platform. This is the first increment of any autonomy campaign, and it is
mostly mechanical (SDWAN already shows the pattern with 31 gate sites).

---

## 6. Policy decisions the operator must make

These change the design, so they are surfaced rather than assumed:

1. **Destructive DR actions.** The ratified rule is that removals never auto-apply. DR wants
   a dead instance reaped and a stale replica retired without a human. Recommendation: keep
   the rule, but define the lane so the **additive** half (replacement up, VIP moved,
   volume reattached) auto-applies within bounds and only the reap waits for approval. The
   project is already healthy when the approval arrives.
2. **Database promotion** is destructive to the old primary's role and can split-brain.
   Recommendation: auto-apply only when the primary is provider-confirmed down **and** the
   replica's lag was under a configured bound at last sample; otherwise page.
3. **Platform self-scaling.** §7 forbids the control plane remediating its own hosting
   stack. Decide whether `PlatformDeployment` scaling applies to hub components at all, or
   only to `cluster_member` spawns.
4. **Public clouds.** Bundle the three SDK gems (adds ~40 MB of dependencies to the hub
   image and widens the supply chain) or drop the adapters from the registry until needed.

---

## 7. Proposed campaign shape (consumer-first, each increment names its consumer)

| # | Increment | Consumer that proves it | Extends |
|---|---|---|---|
| 1 | Uniform gating: declare all writes mutating; gate `BaseSkillExecutor#execute`; exempt or implement the four applier-less lanes | ratchet spec: declared == write set; autonomy tick shows zero false `remediation_stuck` | `Ai::AutonomyGate`, `remediation_validator.rb` |
| 2 | Sense: cpu/load + availability probe into `ProjectMetric`; `instance_unrecoverable` signal; cost sampler | `ProjectSloSensor` fires on a synthetic CPU breach in a smoke seed | heartbeat runtime block, `verify:` probes |
| 3 | Scale lane hardening: project bounds in mission config; scale-out auto within bounds, scale-in approval; retire the `platform_resilience` scale/drain decoys | smoke: memory breach → +1 replica → verification green → fingerprint clears | adaptation lane |
| 4 | Replace-instance lane (DR-1) | smoke: kill a pooled instance's VM → replacement serving within N minutes, reap parked for approval | pool acquire, attach_volume, SDWAN enrol, VIP failover |
| 5 | Project data protection (DR-2): `system_snapshot_volume`, schedule, restore executor | smoke: snapshot → destroy → restore → verify probe green | `provider_volumes#snapshot`, Proxmox snapshot ops |
| 6 | Database promotion (DR-3) | smoke on a `cluster_member` pair: stop primary → replica promoted → `DATABASE_URL` VIP repointed → hub reconnects | `postgres-replica` module, VIP, component-per-instance |
| 7 | Providers: gems or registry guard; credential-lifecycle MCP verbs (operator-gated) | `system_create_provider aws` either works or refuses with a result | `providers/registry.rb` |

Increments 4–6 depend on the SDWAN data-plane campaign delivering at least one enrolled
overlay; without it, VIP failover is structurally a no-op and DR reduces to re-provision.

**Out of scope by ratified policy:** key rotation by agents, DNS repoints, federation
trust acceptance, billing mutations, and any remediation of the control plane's own host.

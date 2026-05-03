# System Extension — High-Level Review & Hardening Plan

**Date:** 2026-04-30
**Last revised:** 2026-05-03 — partially superseded by [`extensions/system/docs/TASKS.md`](../../extensions/system/docs/TASKS.md) and the active stabilization sweep plan at `~/.claude/plans/perform-comprehensive-examination-of-glistening-perlis.md`.
**Scope:** Strategic review of the System extension (operator-side infrastructure management). Walk through intended use, find gaps, identify cleanup, propose hardening.
**Audience:** Operator (Everett) deciding on Phase 1 sign-off and Phase 2 scope.

> **REVISION NOTE (2026-05-03)** — Several 🔴 / 🟡 markers below are stale.
> Specifically:
> - Provider connection `test` action: ✅ shipped (`provider_connections_controller.rb:58-72`)
> - Provider catalog ingestion: ✅ shipped as `sync_catalog` action (`provider_connections_controller.rb:77-89`) backed by `services/system/providers/catalog_sync_service.rb`
> - Frontend "Test credentials" button: ✅ wired
> - M3 Multi-arch image builder: ✅ shipped (`extensions/system/initramfs/build.sh` + dracut configs + 6 artifact families across amd64/arm64)
> - M4 QEMU thin slice: ✅ shipped (`LocalQemuProvider` with Libvirt/Recorder/Disabled runners + 15-spec coverage)
>
> See **§8 What was actually shipped** at the bottom of this doc.

---

## 1. Intent — what System is *for*

Reverse-engineered from the model graph, controller surfaces, and runtime services, the System extension is an **operator-facing infrastructure-management plane** that:

1. **Catalogs** cloud providers and their primitives (regions, AZs, instance types, networks, volume types).
2. **Stores credentials** (`ProviderConnection`) that bind a cloud account to a Powernode account.
3. **Models nodes**: a `Node` is a logical service definition; one or more `NodeInstance`s are the actual running VMs (cloud, physical, or dynamic).
4. **Configures nodes** through a layered system of `NodeArchitecture` (CPU arch), `NodePlatform` (OS), `NodeTemplate` (reusable bundles), `NodeScript` (init/build/sync), `NodeMountPoint` (filesystem), `NodeModule` (versioned config bundles + dependencies + copy paths), and Puppet integration (`PuppetModule` / `PuppetResource`).
5. **Drives state changes** via an `Operation` pipeline — every mutation that touches cloud or hosts is an `Operation` row with an AASM state machine (`pending → scheduled → running → complete | failed | aborted | cancelled`).
6. **Dispatches operations** event-driven: `Operation#after_commit :enqueue_execution` pushes a Sidekiq job directly to Redis (no polling). The worker calls back into `worker_api` to claim and run; `ExecutionDispatcher` routes to one of 13 `System::Runtime::*` services.
7. **Broadcasts live updates** via `SystemChannel` ActionCable channel.
8. **Exposes three API surfaces**: public `/api/v1/system/*` (operator JWT), `/api/v1/system/worker_api/*` (worker token), `/api/v1/system/node_api/*` (instance JWT — what running VMs use to fetch their own config).

### The five primary user journeys

| # | Journey | Models touched | Status |
|---|---------|----------------|--------|
| **A** | **Onboard a cloud account** — register `Provider`, add `ProviderConnection` credentials, ingest catalog (regions/AZs/instance types) | Provider, ProviderConnection, ProviderRegion, ProviderAvailabilityZone, ProviderInstanceType | ✅ **Shipped** — `provider_connections_controller#sync_catalog` + `Providers::CatalogSyncService` |
| **B** | **Define and deploy a node** — create `Node`, attach `NodeTemplate`/`NodeArchitecture`/`NodePlatform`, spin up `NodeInstance` (cloud or physical) | Node, NodeInstance, ProviderRegion, ProviderInstanceType, ProviderNetwork(Subnet) | 🟡 **Frontend cascading complete; backend Operation pipeline works; no real cloud smoke test yet** |
| **C** | **Manage instance lifecycle** — start/stop/reboot/terminate, allocate/release public IPs, attach/detach volumes, SSH exec | NodeInstance, ProviderVolume, Operation | 🟢 **Wired end-to-end (AASM enforced)** |
| **D** | **Distribute software** — author `NodeModule`, version it, build (tar), commit (SCP), apply config to instances | NodeModule(Version), NodeModuleAssignment, ModuleDependency | 🟡 **Build/commit implemented but not exercised end-to-end against real instances** |
| **E** | **Day-2 operations** — sync cloud state into platform DB, run maintenance, view audit log, observe progress live | Operation.events JSON, SystemChannel | 🟢 **Live updates work; sync exists; no metrics on dispatch latency / queue depth** |

---

## 2. Coverage matrix — what works vs. gaps

### 2.1 Backend coverage

| Capability | Models | Service path | Tests | Status |
|---|---|---|---|---|
| Provider CRUD | Provider, ProviderConnection, ProviderRegion, etc. | `*_controller.rb` | provider specs | ✅ |
| Connection credential test | ProviderConnection | `provider_connection.test_connection!` | provider_connection specs | ✅ Wired at `provider_connections_controller#test` (controller:58-72), permission `system.connections.test` |
| Provider catalog ingestion (sync regions/AZs from cloud) | ProviderRegion, ProviderAvailabilityZone, ProviderInstanceType, ProviderNetwork | `Providers::CatalogSyncService.sync_for(connection)` | catalog_sync specs | ✅ Shipped at `provider_connections_controller#sync_catalog` (controller:77-89) |
| Node CRUD | Node | nodes_controller | node_spec | ✅ |
| NodeInstance lifecycle (start/stop/reboot/terminate) | NodeInstance | InstanceControlService → Runtime::ControlInstance | control_instance_spec | ✅ AASM wired |
| Public IP associate/disassociate | NodeInstance | IpManagementService + Runtime::ManagePublicIp | manage_public_ip_spec | ✅ |
| Volume attach/detach/snapshot | ProviderVolume(Snapshot/Member) | VolumeManagementService → Runtime::AttachVolume/DetachVolume | attach/detach specs | 🟡 (snapshot route exists; runtime doesn't use Result, returns hash) |
| Module build (tar) + commit (scp/rsync) | NodeModule, NodeModuleVersion | ModuleBuildService, ModuleCommitService | — | 🟡 Wired but untested against real nodes |
| Module distribute / apply config | NodeModule, NodeInstance | Runtime::SyncModules, Runtime::ApplyConfig | — | 🟡 Runtimes exist but no specs |
| Puppet authoring | PuppetModule, PuppetResource | puppet controllers | puppet_module_spec | 🟡 Frontend missing nested resource form (legacy E-H3) |
| SSH execution | — | SshExecutionService | — | 🟡 Open3 path; no specs |
| Cloud state sync | NodeInstance | CloudSyncService → Runtime::SyncCloudState | sync_cloud_state_spec | 🟡 Service exists; **not yet scheduled** (active sweep P2.1 adds per-account fan-out via `SystemCloudSyncJob` cron `17 * * * *`) |
| Operation audit log | Operation.events JSON | — | operation_spec | 🟡 JSON column — ungrep-able for cross-row audit queries |
| ActionCable live updates | SystemChannel | broadcast_operation_update / progress / node_update / stats_update | — | ✅ |
| Per-account isolation | Account decorator with 17 has_many | — | — | ✅ Just wired (depended_on by every controller) |
| Permissions | 69 system.* permissions | seed migration | — | ✅ Granular |

### 2.2 Frontend coverage

| Page / feature | Status | Notes |
|---|---|---|
| Overview dashboard | ✅ | Uses useSystemStats + useSystemWebSocket |
| Nodes list + detail + create + edit | ✅ | |
| Instance lifecycle (compact + standard) | ✅ | terminate + IP buttons added |
| Cascading provider selects | ✅ | C1 resolved |
| Operations list + tab + live progress | ✅ | |
| Providers / connections | ✅ | "Test credentials" + "Sync catalog" buttons wired |
| Templates | 🟡 | Export action missing (E-H2) |
| Puppet modules | 🟡 | Nested PuppetResource form missing (E-H3) |
| Volumes | 🟡 | `custom_mount_script` + RAID UI missing (E-M2/E-M3) |
| Networks | ✅ | |
| Architectures / Platforms / Scripts / Modules | ✅ | Standard CRUD |
| Audit logs | 🟡 | `AuditLogsPage.tsx` exists but reads `operation.events` JSON column — limited filtering |

### 2.3 What's NOT modeled at all (intent gaps)

These came up by reading the code, not from any plan or audit doc:

1. **Quotas / capacity caps**: no `Account#max_node_instances` or `Account#max_modules` enforcement. A free-tier account could spawn 10,000 nodes.
2. **Cost attribution**: no link from `NodeInstance` to a billing record. Per-instance cost is a Phase-2 concern but nothing in the schema supports it.
3. **Drift detection**: no scheduled "compare cloud state vs. platform state" job that surfaces drift alerts. `CloudSyncService` exists per-instance but isn't run on a schedule.
4. **Secrets distribution**: `NodeInstance#key` is encrypted, but where do new SSH keys come from? No key-generation flow visible.
5. **Bootstrap-token / pairing flow**: Phase 2 customer-install daemon needs this. Already documented as Phase 2, but the model rows (`WorkerEnrollmentToken`) don't exist yet.
6. **Per-cloud-region cache TTL**: `ProviderInstanceType` rows are presumably synced from cloud but never refreshed. Cloud price/capability data drifts.
7. **"Active" view across orgs**: a `system_administrator` role would want to see all operations across all accounts. The current scoping makes this awkward (every query is `current_account.system_*`).

---

## 3. Code cleanliness audit

### 3.1 Inconsistencies that should be normalized

**🔴 Service-return convention split.** 12 runtime services use `System::Runtime::Result`. 10 core services return bare hashes (`{ success: true, ... }`). The runtime services consume the core services and have to translate. Two patterns in one extension is a flag to readers. **Pick one — Result.**

| Returns Result | Returns hash |
|---|---|
| `runtime/control_instance.rb` | `instance_control_service.rb` |
| `runtime/provision_instance.rb` | `provisioning_service.rb` |
| `runtime/sync_cloud_state.rb` | `cloud_sync_service.rb` |
| `runtime/manage_public_ip.rb` | `ip_management_service.rb` |
| `runtime/attach_volume.rb`, `runtime/detach_volume.rb` | `volume_management_service.rb` |
| `runtime/build_module.rb` | `module_build_service.rb`, `module_commit_service.rb` |
| `runtime/execute_ssh_command.rb` | `ssh_execution_service.rb` |
| `runtime/apply_config.rb`, `runtime/sync_modules.rb` | `node_maintenance_service.rb`, `instance_maintenance_service.rb` |
| `execution_dispatcher.rb` | `database_backup_service.rb`, `image_creation_service.rb` |

**🔴 Internal `sync_cloud_state` controller writes raw status.** The internal controller (`internal/system/node_instances_controller.rb#sync_cloud_state`, ~line 138) does `@instance.update!(status: result[:status], ...)` — bypasses AASM. With the AASM refactor in place, this is a regression vector: `result[:status]` could be any string and break the state machine invariants. Should route through `Runtime::SyncCloudState` or call AASM events.

**🟡 Operation `events` JSON column.** Single-row audit log inside a JSON array. Works today but: (a) can't `WHERE` filter ("show me all 'failed' events for account X this week"), (b) no index, (c) PG `jsonb_array_elements` is awkward for analytics. If audit log volume matters, extract to `system_operation_events` table.

**🟡 `useOperationPolling.ts` filename.** The hook was renamed internally to `useOperations`/`useSingleOperation` (no polling — uses ActionCable subscription) but the filename still says "polling". Misleading.

### 3.2 Dead and vestigial code

| Item | Lines | Disposition |
|---|---|---|
| 17 worker jobs in core `worker/app/jobs/system/` | ~1,500 | Awaiting operator authorization to delete (documented in `legacy_audit.md` §12) |
| `Operation#last_event` method | 3 | Unused outside specs; trim |
| Spec `:running` factory state still constructs an op with `status: 'running'` and `progress: 50` | — | Slightly wrong because AASM doesn't validate transition when factory force-sets status; harmless for now but tests should prefer `op.start!` over factory |
| `frontend/src/features/system/hooks/useOperationPolling.ts` filename | — | Rename to `useOperations.ts` |

### 3.3 Mostly-clean — leave for now

- 32 models all under 200 lines except `Operation` (220) and `NodeInstance` (189). Both are fine.
- 23 public controllers, all under 200 lines now that `internal/.../node_instances_controller.rb` was decomposed.
- Provider adapter base class is well-documented; AWS/GCP/Mock implementations follow it.

---

## 4. Hardening audit

### 4.1 Security

**🔴 Public API exposes `Operation#fail!` / `abort!` / `cancel!` / `complete!` to operators.** Routes:
```ruby
resources :operations, only: %i[index show create] do
  member do
    post :start
    post :complete   # ← user can write a fake "complete" status
    post :fail       # ← user can write a fake "failure" status
    post :abort
    post :cancel
  end
end
```
A user with `system.infra_operations.control` could mark a still-running provisioning as `complete` server-side, breaking the audit trail. **Verdict:** keep `cancel` (legitimate user action), drop `complete`/`fail`/`abort`/`start` from the public API. Worker token already has them via `worker_api/operations`.

**🟡 No worker-extension capability check.** The broken `require_infrastructure_worker!` was removed (correctly — it called a method that didn't exist). Per-action permission gates cover authorization, but any Worker token now has access to `/system/worker_api/*` if it has `system.operations.execute` permission. Defense-in-depth: a `Worker#has_capability?(:system)` method that checks for any `system.*` permission, evaluated at the BaseController. Not blocking; nice-to-have.

**🟡 No idempotency token on `POST /system/operations`.** A retry from a flaky network would create two ops, both fire. Easy to add: `idempotency_key` column with a unique-by-account index, returns existing op on duplicate insert.

**🟢 SSH key encryption.** `NodeInstance#key` uses Rails `encrypts` — keys are at-rest encrypted. ✅

**🟢 Provider credentials.** `ProviderConnection` per-account scoping prevents cross-tenant credential leak. Verified in account_decorator.

### 4.2 Race conditions

**🟢 Operation claim race.** Solved by AASM `whiny_transitions: true` + atomic `start!` save: two workers racing both call `op.start!`, exactly one wins (the second raises `AASM::InvalidTransition`). Dispatcher catches and returns 409 Conflict. ✅

**🟡 NodeInstance status race.** Two workers both claiming the same instance for, say, `start` would both transition `stopped → starting` — but `whiny_transitions: true` means the second raises. Need to verify `InstanceControlService` rescues this. Not currently rescued — would propagate as 500. Should be a 409.

**🟡 Operation `events` JSON append.** Two concurrent `add_event` calls without row-level lock = lost-update. Likely rare (each operation is owned by one worker at a time), but worth a `with_lock` block or moving events to a separate table.

### 4.3 Error handling

**🔴 Sidekiq job timeout policy is undocumented.** Plan said 60-min per-queue timeout for `system`. `worker/config/sidekiq.yml` doesn't currently set this. Long provisioning ops that exceed the default 30s+ will be killed. **Configure explicitly.**

**🔴 No retry/backoff on Operation execution.** `SystemExecuteOperationJob` declares `retry: 0` (correct — operation state machine is source of truth). But: when `Runtime::ProvisionInstance` fails because of a transient AWS API blip, the operation transitions to `:failed` permanently. There's no "retry this transient failure" path. **Add:** distinguish transient (cloud API timeout) from permanent (validation rejection) in runtime services; allow operator-initiated re-run that creates a new operation linked to the failed one (`retry_of_operation_id`).

**🟡 Reaper handles "stuck pending" and "stuck running" but not "scheduled-but-never-started".** AASM has a `:scheduled` state but nothing in the platform actually puts ops into it. Either remove the state or implement scheduled-execution (which would be useful for cron-style infra ops).

**🟡 AzureProvider raises `NameError` at runtime.** Faraday < 2.0 dependency conflict with the platform's Faraday ~> 2.0. Already documented. Either drop Azure support entirely from the registry or vendor a Faraday-2-compatible Azure client. Currently the registry would let you create an Azure ProviderConnection that crashes on first use.

### 4.4 Observability

**🔴 No metrics on dispatch pipeline.** No counters for: ops created/sec, ops completed/sec, ops failed/sec, average dispatch latency (created → start), average execution latency (start → complete), queue depth, claim conflicts. **Add:** instrument `ExecutionDispatcher` and `Operation#after_commit :enqueue_execution` with `Rails.logger.tagged("metrics")` at minimum, ideally StatsD/OpenTelemetry.

**🔴 Operation audit log isn't a metric source.** All events live inside one JSON column per operation. Aggregating "all failed-state transitions in the last hour" requires a full table scan + JSON traversal. Per §3.1, extract events to a dedicated table.

**🟡 No `claimed_by_worker_id` on Operation.** When debugging "which worker took this op?" the answer is "look at the Sidekiq jid in the events JSON column, then cross-reference Sidekiq web UI." Add a column.

**🟢 ActionCable broadcasts on every state change.** Frontend gets live updates. ✅

### 4.5 Data integrity

**🔴 Account `dependent: :destroy` cascade on system_*.** Deleting an Account CASCADE-deletes 17 association types including `system_node_instances`. But cloud resources (the actual EC2 instance) are NOT terminated server-side. **Net effect:** account deletion = orphan cloud resources = ongoing AWS charges. **Mitigation:** before allowing Account destroy, require either zero active instances OR require an explicit "terminate all" action that completes its operation pipeline first. Or change `dependent: :destroy` to `dependent: :restrict_with_error` — at minimum the cascade should be intentional.

**🟡 No soft-delete on `Operation`.** Once an Operation is destroyed (e.g., via Account cascade), the audit trail is gone. Audit logs typically need indefinite retention. Consider `acts_as_paranoid` or move to immutable event-store table.

---

## 5. Prioritized plan

Each item: **Title** — *gap reference* — **effort** (S = <1d, M = 1–3d, L = >3d) — **risk if skipped**.

### P0 — security + data integrity (do before any production rollout)

1. **Drop `start`/`complete`/`fail`/`abort` from public Operations API; keep only `cancel`.** §4.1 — **S** — Risk: operator forges audit trail.
2. **Replace direct `update!(status: ...)` in `internal/.../sync_cloud_state` with AASM events.** §3.1 — **S** — Risk: state-machine invariants violated by internal back-channel.
3. **Add idempotency token to `POST /system/operations`.** §4.1 — **S** — Risk: duplicate-billing duplicate-provisioning incidents.
4. **Configure 60-min per-queue Sidekiq timeout for `system`.** §4.3 — **S** — Risk: long provisioning silently killed.
5. **Replace `Account dependent: :destroy` cascades with `:restrict_with_error` + explicit "drain" flow.** §4.5 — **M** — Risk: orphaned cloud resources, ongoing AWS charges after account delete.
6. **Drop or fix Azure provider:** decide between (a) remove from `Providers::Registry::PROVIDER_CLASSES` until Phase 2, or (b) vendor a Faraday-2-compatible client. §4.3 — **S** (drop) or **L** (fix) — Risk: 500 on use.

### P1 — completeness + standards (do alongside Phase 1 sign-off)

7. **Provider catalog ingestion service** (`Providers::CatalogSyncService.sync_for(connection)`): pulls regions, AZs, instance types from the cloud and upserts. §1A, §2.1 — **M** — Critical missing capability for journey A.
8. **Normalize service return convention to `Runtime::Result`.** Update 10 core services. §3.1 — **M** — Affects readability + future maintenance.
9. **Frontend gaps:**
   - **E-H1** Provider-connection "Test credentials" button — **S**
   - **E-H2** Template Export — **S** (frontend) + **S** (backend route + serializer)
   - **E-H3** Puppet PuppetResource nested form — **M**
10. **Add `claimed_by_worker_id` column to Operation + populate in `start!` callback.** §4.4 — **S**.
11. **Real-cloud sandbox smoke test** (sandbox AWS): provision a `t2.nano`, observe the operation transitions through `pending → running → complete`, terminate it, verify audit log. §1.B, §2.1 — **M** (operator-driven, not Claude).

### P2 — observability + cleanup (good hygiene; not blocking)

12. **Extract `Operation.events` JSON column to a `system_operation_events` table** with `operation_id`, `event_type`, `message`, `data jsonb`, `timestamp`. Migrate existing data. §3.1, §4.4 — **M**.
13. **Instrument dispatch pipeline with metrics** (Rails log tags or StatsD). §4.4 — **S** for tags, **M** for full StatsD.
14. **Audit-and-delete the 17 vestigial worker jobs in core `worker/app/jobs/system/`.** Already documented; needs operator authorization. §3.2 — **S**.
15. **Rename `useOperationPolling.ts` → `useOperations.ts`.** §3.1 — **S**.
16. **Spec coverage for SSH execution and module build/commit** end-to-end (mocked Open3). §2.1 — **M**.

### P3 — feature additions (open-ended; demand-driven)

17. **Bulk operations**: start/stop N instances in one API call. §1 (gap) — **M** — Need: operator scale.
18. **Quota model**: `Account#system_quota_limits` + enforcement in controllers. §1 (gap) — **M** — Need: SaaS scale.
19. **Drift detection job**: scheduled `CloudSyncService.sync_all_active` + diff alert. §1 (gap) — **M** — Need: drift incidents.
20. **Operation retry**: schema for `retry_of_operation_id`, "Retry" button on failed ops, transient-vs-permanent classification in runtimes. §4.3 — **M**.
21. **Scheduled operations**: actually use the `:scheduled` AASM state. §4.3 — **L**.

---

## 6. Recommended execution order

**Sprint 1 (P0 + low-effort P1):** items 1–6, 9 (E-H1), 10. ~3–5 days. Closes every security/data-integrity issue and lands the most user-visible frontend gap.

**Sprint 2 (P1 completeness):** items 7, 8, 9 (E-H2, E-H3), 11. ~5–8 days. Unblocks journey A (catalog ingestion) and finishes Phase 1 frontend parity.

**Sprint 3 (P2 hygiene):** items 12–16. ~3–5 days. Sets up observability and deletes dead code.

**P3 deferred** until customer/operator demand surfaces.

---

## 7. Sign-off criteria for Phase 1 retirement of `powernode-server`

After Sprint 1 + Sprint 2:

- [ ] All P0 items closed.
- [ ] At least one real-cloud smoke test (sandbox AWS) succeeds end-to-end.
- [ ] Provider catalog ingestion works for AWS (other clouds can follow).
- [ ] Spec count: 194 → ~250 (added: SSH, module build/commit, catalog sync, idempotency).
- [ ] Frontend audit `legacy_view_audit.md` shows zero High-priority gaps.
- [ ] Operator says "ship it."

`powernode-agent` stays as Phase 2 reference. Per operator directive, no destructive ops on either legacy repo.

---

*Generated 2026-04-30 from a structural audit of `extensions/system/` against journeys decoded from the model graph and controller inventory. No code was changed during this audit; the implementation plan above is for review and prioritization.*

---

## 8. What was actually shipped (2026-05-03 update)

This appendix corrects the stale 🔴 / 🟡 markers above. Cross-reference the
authoritative status doc at `extensions/system/docs/TASKS.md`.

### Shipped between 2026-04-30 and 2026-05-03

| Item | Sprint-1 priority | Where it lives now |
|---|---|---|
| Drop `start`/`complete`/`fail`/`abort` from public Operations API | P0 #1 | Migrated as part of `system_operations` → `system_tasks` AASM rename (migration `20260430130000_rename_system_operations_to_tasks.rb`); operator-side keeps `cancel` only |
| Replace direct `update!(status: …)` with AASM events | P0 #2 | Internal sync_cloud_state path now routes through `Runtime::SyncCloudState` |
| Configure 60-min per-queue Sidekiq timeout | P0 #4 | Long-running op guardrails documented + reaper path; see `worker/config/sidekiq_system.yml:12-31` |
| Provider catalog ingestion service | P1 #7 | `Providers::CatalogSyncService.sync_for(connection)` — shipped + spec'd. Wired into `provider_connections_controller#sync_catalog` |
| Frontend E-H1 "Test credentials" button | P1 #9 | Wired |
| `claimed_by_worker_id` on Task (renamed from Operation) | P1 #10 | Migration `20260429184000_add_claimed_by_to_system_operations.rb` |
| QEMU smoke test | P1 #11 | `LocalQemuProvider` runner triplet (Libvirt/Recorder/Disabled) + 15-spec integration coverage; M3+M4 Ubuntu 24.04 overlay-union root with system-base + nginx modules verified |

### Major schema migrations landed since 2026-04-30

- `system_operations` → `system_tasks` (AASM, polymorphic, `claimed_by_worker_id`)
- `bootstrap_tokens` (1-hour TTL, SHA-256 hashed, single-use, audit-logged)
- `node_certificates` (mTLS plumbing, 90-day TTL, auto-rotate)
- `module_artifacts` (OCI digest + fs-verity hash + cosign trust policy)
- `cves` + `cve_exposures` (CVE response pipeline foundation)
- `fleet_events` (90d routine / 365d critical retention)
- `slo_definitions` (SLO tracking)
- `consent_budgets` (per-module daily decision ceiling)
- `physical_enrollment` columns on bootstrap path
- `disk_image_publications` + `disk_image_webhooks`

### Recent CI/release work

- Disk-image publication pipeline (Phase 2 chunks 1-4): direct upload, OCI ingest, retention sweeps, Gitea Actions workflow with cosign-signed artifacts
- ARM64 UEFI build path optional in CI (Gitea blob limit accommodation)
- Multi-arch initramfs builder: 6 artifact families × amd64/arm64 reproducible

### Still open (post-2026-05-03 sweep)

Active comprehensive stabilization sweep. See `extensions/system/docs/TASKS.md`
"Active stabilization sweep — May 2026" section.

The remaining items from this doc's §5 (P0–P3) that are NOT yet closed:

- **P0 #3** Idempotency token on `POST /system/tasks` — open
- **P0 #5** `Account dependent: :destroy` cascade audit — open
- **P0 #6** Azure provider Faraday-2 fix or removal — open
- **P1 #8** Service return convention normalization — partial
- **P2 #12** Extract `task.events` JSON to dedicated table — open
- **P2 #13** Metrics instrumentation — open
- **P3 #17–21** Bulk operations, quotas, drift detection, retry, scheduled ops — deferred

These are tracked but not in the active sweep scope.

> **ARCHIVED 2026-05-01** — Preserved for historical context. See [current docs](../../README.md) for current state.

# Legacy `powernode-server` → System:: Extension Audit

**Date:** 2026-04-29
**Scope:** Rails 4.2.4 legacy app at `~/Drive/Projects/powernode-server` vs. the System extension at `extensions/system/`.
**Purpose:** Catalog what was ported, what was deliberately dropped, what's pending. Reference document for retiring the legacy repo.

> **Verification status:** This audit synthesizes a structural diff plus the in-platform changes made during the System:: migration. Spot-check claims about specific functional behaviors (e.g., "preserved unchanged") against the live code before relying on them in production work.

---

## Summary

- **Models:** ~39 of ~41 legacy models have a System:: equivalent or are owned by core. The 2 deliberate omissions are billing-adjacent (`credit_card.rb`, `page.rb` belongs to CMS).
- **Controllers:** All RESTful CRUD controllers have System:: equivalents. The legacy `api/agent_v1/*` and `api/node_v1/*` controllers are now under `api/v1/system/{worker_api,node_api}/`.
- **Services:** Stripe billing services are deliberately NOT ported (out of scope for System; belongs in a future Payment extension).
- **Authorization:** CanCanCan abilities (245 LOC, 36+ roles) replaced by 69 string-keyed permissions seeded by extension migration `20260429120000_seed_system_extension_permissions_and_flags.rb`.
- **Authentication:** Agent SCrypt key auth replaced by JWT-based Worker tokens (already in core).
- **Versioning:** `acts_as_versioned` replaced by explicit `system_node_module_versions` table + `ModuleVersionService`.
- **File storage:** Paperclip + custom `:uuid_partition/:filename` replaced by platform's storage-provider abstraction.
- **Operation dispatch:** No more cron polling. Event-driven via `Operation#after_commit` → `WorkerDispatch` → Redis push → worker.

## Coverage classifications

- ✅ **COVERED** — equivalent exists in System:: extension
- 🔄 **PORTED-DIFFERENTLY** — same concept, new shape; key difference noted
- ❌ **MISSING** — known gap, not yet addressed
- ⚠️ **DROP** — deliberately not porting

---

## 1. Models

### Core / multi-tenant identity

| Legacy | New location | Status | Notes |
|---|---|---|---|
| `account.rb` | core | ✅ | AASM Account states preserved |
| `user.rb` | core | ✅ | Devise + roles unchanged |
| `agent.rb` | replaced by `Worker` (core) | 🔄 | SCrypt key → JWT token; the four legacy roles (agent / poller / proxy / store) are still meaningful as Worker capabilities |
| `plan.rb` | core (billing) | ✅ | `enforce_limits` DSL refactored into subscription service |
| `account_delegation.rb` | core | ✅ | Cross-account access |
| `invitation.rb` | core | ✅ | Email invites |
| `credit_card.rb` | — | ⚠️ DROP | PCI scope; future Payment extension owns payment-method storage |
| `page.rb`, `page_resource.rb` | core CMS | ✅ | Migrated |

### Node infrastructure

| Legacy | New location | Status | Notes |
|---|---|---|---|
| `node.rb` | `extensions/system/server/app/models/system/node.rb` | ✅ | Polymorphic ops preserved |
| `node_instance.rb` | `system/node_instance.rb` | ✅ | Paperclip removed; ssh_ip + admin_user retained; geocoding preserved |
| `node_template.rb` | `system/node_template.rb` | ✅ | Template + module subscriptions |
| `node_platform.rb` | `system/node_platform.rb` | ✅ | OS/init/sync scripts |
| `node_architecture.rb` | `system/node_architecture.rb` | ✅ | Boot + image attachments via storage provider |
| `node_script.rb` | `system/node_script.rb` | ✅ | Script content + checksums |
| `node_mount_point.rb`, `node_module_copy_path.rb` | same names under `system/` | ✅ | Shape preserved |

### Module system (config / packages)

| Legacy | New location | Status | Notes |
|---|---|---|---|
| `node_module.rb` (333 LOC) | `system/node_module.rb` | 🔄 | `acts_as_versioned` removed; explicit `NodeModuleVersion` table tracks versions |
| `node_module_subscription.rb` | `system/node_module_assignment.rb` | 🔄 | Renamed for clarity |
| `node_module_dependency.rb` | `system/module_dependency.rb` | ✅ | Topological resolution moved to `DependencyResolutionService` |
| `node_module_category.rb` | `system/node_module_category.rb` | ✅ | Unchanged |
| `node_template_module_subscription.rb` | `system/template_module.rb` | 🔄 | Renamed |

### Cloud providers

| Legacy | New location | Status |
|---|---|---|
| `provider.rb` | `system/provider.rb` | ✅ |
| `provider_connection.rb` | `system/provider_connection.rb` | ✅ |
| `provider_region.rb`, `provider_availability_zone.rb` | same names | ✅ |
| `provider_instance_type.rb` | `system/provider_instance_type.rb` | ✅ |
| `provider_volume.rb` (+ types/snapshots/members) | `system/provider_volume*.rb` | ✅ |
| `provider_network.rb`, `provider_network_subnet.rb` | same names | ✅ |
| `*_subscription.rb` (volume-type / instance-type) | `system/region_volume_type.rb`, `system/region_instance_type.rb` | 🔄 Renamed |

### Puppet integration

| Legacy | New location | Status |
|---|---|---|
| `puppet_module.rb` | `system/puppet_module.rb` | ✅ |
| `puppet_resource.rb` | `system/puppet_resource.rb` | ✅ |
| `node_module_puppet_module_subscription.rb` | `system/module_puppet_assignment.rb` | 🔄 Renamed |

### Operations

| Legacy | New location | Status | Notes |
|---|---|---|---|
| `operation.rb` (46 LOC, polymorphic, statuses=pending/running/complete/failed/abort) | `system/operation.rb` | 🔄 | State machine expanded (pending/scheduled/running/complete/failed/aborted/cancelled). Added `after_commit` for event-driven dispatch + ActionCable broadcasts |

### Authorization

| Legacy | New approach | Status |
|---|---|---|
| `ability.rb` (CanCanCan, 245 LOC, 36+ role checks) | Permission rows seeded by `20260429120000_seed_system_extension_permissions_and_flags.rb` (69 permissions) + Flipper flags `system_mode`, `system_operation_dispatch`, `system_provisioning`, `system_module_distribution` | 🔄 |

---

## 2. Controllers

### Operator-facing CRUD (RESTful)

All ~22 legacy resource controllers map to `extensions/system/server/app/controllers/api/v1/system/<resource>_controller.rb`. Standard `index/show/create/update/destroy`. Member actions for instance lifecycle (`start`/`stop`/`reboot`) and volume actions (`attach`/`detach`/`snapshot`) are preserved.

### Agent / worker API (legacy: `api/agent_v1/*`)

| Legacy endpoint | New endpoint | Status |
|---|---|---|
| `GET /api/agent_v1/accounts/:id/operations` | `GET /api/v1/system/worker_api/operations/pending` | 🔄 |
| `PUT /api/agent_v1/operations/:id` (monolithic) | Split into `POST .../start`, `PUT .../progress`, `POST .../complete`, `POST .../fail`, `POST .../events` | 🔄 |
| `POST /api/agent_v1/operations/:id/execute` | NEW — `POST /api/v1/system/worker_api/operations/:id/execute` | ✅ NEW |
| Module + image upload/download | `worker_api/modules` and `worker_api/volumes` member actions | ✅ |
| Auth: HTTP Basic + SCrypt | Auth: `Authorization: Bearer swt_*` (Worker token) | 🔄 |

### Node-facing API (legacy: `api/node_v1/*`)

All endpoints (instance config, authorized_keys, host_keys, modules, scripts, mount_points, status) are present at `api/v1/system/node_api/`. Auth mechanism upgraded from CIDR allowlist + token to JWT Instance tokens (`X-Instance-Token` or `Authorization: Bearer` with `type: "instance"`).

---

## 3. Services

### Ported / mapped to System:: services

| Legacy intent | New service | Status |
|---|---|---|
| Stripe customer sync | — | ⚠️ DROP — Payment extension scope |
| Stripe plan sync | — | ⚠️ DROP — Payment extension scope |
| Stripe webhook handling | — | ⚠️ DROP — Payment extension scope |
| Module build (implicit, in operations) | `system/module_build_service.rb` (real `tar -czf` packaging) | ✅ |
| Module commit (SSH-based deploy) | `system/module_commit_service.rb` (real SCP via `system/ssh_execution_service.rb#scp_file`) | ✅ |
| Module dependency walk | `system/dependency_resolution_service.rb` | ✅ |
| Cloud instance provisioning | `system/provisioning_service.rb` + `system/providers/*` (AWS / GCP / OpenStack / Mock; Azure deferred) | ✅ |
| Instance lifecycle | `system/instance_control_service.rb` | ✅ |
| Cloud reconciliation | `system/cloud_sync_service.rb` | ✅ |
| Module versioning | `system/module_version_service.rb` | ✅ |
| Volume management | `system/volume_management_service.rb` | ✅ |
| SSH execution | `system/ssh_execution_service.rb` (Open3 + system `ssh`; gated by `SYSTEM_SSH_ENABLED`) | ✅ |
| Operation dispatch (NEW) | `system/execution_dispatcher.rb` (frozen-hash command → runtime registry) | ✅ NEW |
| Operation enqueue (NEW) | `system/worker_dispatch.rb` (raw Sidekiq-format JSON push to Redis; no sidekiq gem on server) | ✅ NEW |
| Runtime services (NEW) | `system/runtime/{provision,control,build_module,commit_module,attach_volume,detach_volume,execute_ssh_command,apply_config,sync_modules,sync_cloud_state,operation_dispatcher,result}.rb` | ✅ NEW |

---

## 4. Helpers

`app/helpers/application_helper.rb`, `app/helpers/nodes_helper.rb` — **⚠️ DROP**. The frontend is now React/TypeScript; server-side ERB/HAML view helpers don't apply.

---

## 5. Configuration

| Legacy | New approach | Status |
|---|---|---|
| `config/config.yml.example` (~90 settings) | Environment variables + Rails credentials + per-account/connection records | 🔄 |
| Per-account `encryption_key` + `key_pepper` | Account-level encryption key kept; pepper inheritance via `Security::CredentialEncryptionService` | ✅ |
| `devise_pepper`, `devise_secret_key` | Standard Rails credentials | ✅ |
| `newrelic.yml` | Sentry + platform metrics | 🔄 |

---

## 6. Migrations (legacy)

41 legacy migrations. None are "ported as-is" — the equivalent schema was created fresh in System:: migrations:

- `20251215200001_create_powernode_system_node_core.rb`
- `20251215200002_create_powernode_system_providers.rb`
- `20251215200003_create_powernode_system_modules.rb`
- `20251215200004_create_powernode_system_operations_storage.rb`
- `20251215200005_create_powernode_system_puppet.rb`
- `20251216100001_add_module_versioning_system.rb`
- `20251216200001_add_system_model_enhancements.rb`
- `20260429120000_seed_system_extension_permissions_and_flags.rb`

Two legacy migrations introduced concepts worth specifically calling out:
- `20140903200846_add_lock_spec_to_node_module.rb` — **preserved** in `system_node_modules.lock_spec`.
- `20150401200153_change_active_merchant_to_stripe.rb` — **dropped** (billing scope).

---

## 7. Tests

The legacy repo's `spec/` directory contains config files only (`spec_helper.rb`, `spec.opts`, `rcov.opts`); no actual spec files were present in the snapshot examined. New System:: extension specs live under `extensions/system/server/spec/{models,services,integration}/system/` (26 files migrated from core in the migration phase). Task #12 (write 10-15 new spec files for runtime services + jobs) remains pending.

---

## 8. Distinctive behaviors

### Preserved

- Per-account encryption key (data-at-rest isolation).
- Polymorphic `Operation#operable` with `events` JSONB log + `add_event(type, message, data)`.
- Node variety enum (`cloud` / `physical` / `dynamic`).
- Geocoding on instances (lat/long from IP) — preserved where used.
- Module dependency DAG resolution.

### Replaced (functionally equivalent, different mechanism)

- Agent SCrypt auth → Worker Bearer JWT (`swt_*` token format).
- `acts_as_versioned` → explicit `system_node_module_versions` table.
- Paperclip `:uuid_partition/:filename` → storage-provider abstraction.
- CanCanCan abilities → string permissions + Flipper flags.
- Cron-polling agent dispatch → event-driven `after_commit` enqueue.
- Devise async email → core mail-delivery worker service.

### Deliberately dropped

- Stripe billing services (Payment extension scope).
- Bowerfile (frontend asset tooling — replaced by Vite + npm).
- `cancan` gem dependency (replaced).
- `paperclip` gem dependency (replaced).
- `acts_as_versioned` gem dependency (replaced).
- `devise-async` (handled differently in core).

---

## 9. Phase 2 reference: `powernode-agent`

The `~/Drive/Projects/powernode-agent` repo is **NOT** retired. It remains as the reference implementation for Phase 2's standalone customer-installable daemon. Phase 1's worker-extension model handles operator-side deployments; Phase 2 will extract the runtime services into a Ruby gem (`powernode-system-runtime`) and ship a thin CLI in a new repo (likely `powernode-system-agent`) that consumes the gem, authenticates as a Worker via bootstrap-token claim, and runs the same dispatch protocol.

---

## 10. Retirement checklist for `powernode-server`

Before archiving the legacy repo:

- [x] All System:: models load (verified via `rails runner` + ExtensionRegistry)
- [x] 206 routes mounted via extension's `routes.rb`
- [x] Permission seeding migration ran (130+ system.* permissions in DB; 4 Flipper flags)
- [x] Event-driven dispatch end-to-end smoke test passes (verified by Redis queue inspection)
- [x] `npx tsc --noEmit` clean
- [x] Task #12: extension RSpec specs for runtime services + jobs (11 spec files, 113 examples; surfaced + fixed real bugs in `ExecutionDispatcher` unsupported-command path and the `Operation::COMMANDS`/`COMMAND_REGISTRY` whitelist mismatch)
- [ ] Manual smoke test against a sandbox AWS account (real cloud SDK call) — blocker for full Phase 1 sign-off
- [x] Document retirement in `docs/system/legacy_audit.md` ← *this file*
- [ ] Archive on Gitea: mark `develop` read-only, add `DEPRECATED.md` pointing to extension — **requires explicit operator authorization**

---

## 11. Items worth porting that remain pending

### High priority

- ~~**Cascading cloud-provider selects**~~ — ✅ Resolved in `CreateInstanceModal.tsx:124-218`. Task #29.
- ~~**Quick-action terminate / IP associate / IP disassociate**~~ — ✅ Resolved in `NodeInstanceControls.tsx` (terminate with two-click confirm) + `NodeDetailModal.tsx` IP rows (associate / disassociate, gated by `system.instances.control` and cloud variety). Backend wired through new `Runtime::ManagePublicIp`. Task #30.
- ~~**RSpec coverage** for runtime services and jobs~~ — ✅ Resolved. 11 specs / 113 examples passing. Task #12.

### Medium priority

- **Set-primary-instance** action (legacy had per-node primary instance).
- **Cleanse / sync** instance lifecycle actions.
- **Module subscription management** (subscribe / unsubscribe + copy-path config).
- **Real-cloud smoke test** with sandbox AWS / GCP credentials.

### Low priority

- Module version operations (restore / delete / purge).
- Physical-instance image creation / boot-image download.
- Puppet modules display in node detail view.
- Volumes + mount points display on instance cards.

---

## 12. Orphaned worker jobs in core (pending cleanup decision)

During final sweep, 16 pre-migration worker job classes were found in `worker/app/jobs/system/` that have NO external callers, NO sidekiq cron entries, and NO specs. They duplicate functionality now owned by the extension's `Runtime::*` services and the event-driven `SystemExecuteOperationJob` → `ExecutionDispatcher` chain.

| File | Class | Status |
|---|---|---|
| `cloud_instance_sync_job.rb` | `System::CloudInstanceSyncJob` | superseded by `Runtime::SyncCloudState` |
| `image_create_job.rb` | `System::ImageCreateJob` | superseded by Phase 2 daemon path; no callers |
| `maintenance_job.rb` | `System::MaintenanceJob` | polling pattern, superseded |
| `maintenance_scheduler_job.rb` | `System::MaintenanceSchedulerJob` | "replicates legacy powernode-agent poller" — explicitly the pattern we eliminated |
| `module_build_job.rb` | `System::ModuleBuildJob` | superseded by `Runtime::BuildModule` |
| `module_commit_job.rb` | `System::ModuleCommitJob` | superseded by `Runtime::CommitModule` |
| `node_instance_control_job.rb` | `System::NodeInstanceControlJob` | superseded by `Runtime::ControlInstance` |
| `node_instance_exec_job.rb` | `System::NodeInstanceExecJob` | superseded by `Runtime::ExecuteSshCommand` |
| `node_instance_ip_job.rb` | `System::NodeInstanceIpJob` | superseded by `Runtime::ManagePublicIp` |
| `node_instance_maintenance_job.rb` | `System::NodeInstanceMaintenanceJob` | polling pattern, superseded |
| `node_instance_provision_job.rb` | `System::NodeInstanceProvisionJob` | superseded by `Runtime::ProvisionInstance` |
| `node_instance_sync_job.rb` | `System::NodeInstanceSyncJob` | superseded by `Runtime::SyncCloudState` |
| `node_maintenance_job.rb` | `System::NodeMaintenanceJob` | polling pattern, superseded |
| `system_health_check_job.rb` | `System::SystemHealthCheckJob` | unscheduled; ad-hoc health check, not currently invoked |
| `volume_health_check_job.rb` | `System::VolumeHealthCheckJob` | unscheduled |
| `volume_management_job.rb` | `System::VolumeManagementJob` | superseded by `Runtime::AttachVolume` / `Runtime::DetachVolume` |

Total: ~1,500 lines of dead code. Recommended action: delete after operator confirmation.

**Verification commands run:** `grep -rln <classname>` across the entire repo returned only self-references inside `worker/app/jobs/system/`. `worker/config/sidekiq.yml` has no `:schedule:` block referencing any of them. No specs exist for them.

---

## Conclusion

The System:: extension owns the entire infrastructure-management surface area that `powernode-server` previously held. Code that was deliberately dropped is documented above; deferred items have follow-up tasks.

**Archival readiness as of this update:** All non-destructive prerequisites are met (specs, type checks, route mounts, dispatch smoke test, audit doc). The remaining gates are:

1. **Manual real-cloud smoke test** against a sandbox AWS account (provisions a `t2.nano`, observes the operation transitions through `pending → running → complete`, terminates it). Run from a workstation with sandbox credentials configured in a `System::ProviderConnection`. Not gated on Claude Code — operator-driven one-shot.
2. **Operator authorization** for the destructive Gitea archival actions: marking `develop` read-only, adding `DEPRECATED.md`, and toggling `archived: true` on the Gitea repo. Reversible only by a Gitea admin, so explicit go-ahead is required.

When ready, the archival sequence is: (a) push a final commit to `powernode-server` adding `DEPRECATED.md` that links back to `extensions/system/` in this repo; (b) `gh repo edit --archive` (or the Gitea equivalent — `platform.update_gitea_repository` with `archived: true`); (c) leave `powernode-agent` as-is per Section 9.

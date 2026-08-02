# CI builder record accumulation — cleanup 2026-08-02

Operator-approved cleanup of accumulated `ci-native-builder*` fleet records on ops-hub,
plus the two defects the data exposed. Cleanup is done; **both defects are now fixed in
`System::InstancePoolService`** (see the two sections below) — but the fix is only in the
repo. ops-hub runs code from 2026-07-28, so nothing changes there until a deploy.

## What was there

94 of the platform's 97 `System::Node` records were CI builder pool members, with one
`System::NodeInstance` each, accumulated over 15 days (2026-07-18 → 2026-08-02).

| Instance status | Count | Created | Fresh heartbeat |
|---|---|---|---|
| terminated | 72 | 07-18 → 08-01 | 0 |
| error | 21 | 07-18 → 08-01 | 0 |
| running | 1 | 08-02 | 1 ✓ |

Only the single `running` builder had a live VM (dna VMID 9002). The other 93 were
records for VMs that no longer exist.

## What was removed

93 nodes and everything hanging off them, in one transaction:

| Table | Rows |
|---|---|
| `system_nodes` | 93 |
| `system_node_instances` | 93 |
| `system_node_module_assignments` | 372 |
| `system_node_certificates` | 90 |

`system_bootstrap_tokens` (92 rows) resolved on their own — `node_id` is `ON DELETE CASCADE`,
`node_instance_id` is `SET NULL`.

Left untouched: the live builder, plus ops-hub, ops-cell and dev-cell. Post-state is 4 nodes
and 4 instances, all with fresh heartbeats; ops-hub `/up` 200 in 15 ms immediately after.

**Rollback data:** `/persist/backups/builder-cleanup-20260802/{nodes,instances}.json` on
ops-hub (0700, postgres-owned). Key-material columns are deliberately excluded per the
crypto-material rule — `ssh_key`, `ssh_host_key`, both fingerprints, instance `key`, and
`enrollment_token_id`. The backup answers "what existed", it does not restore working nodes.
Those VMs are gone, so that distinction costs nothing.

### How, and why not the obvious way

`System::NodeMaintenanceService#task_resource_cleanup` is the built-in path, but it does not
fit this case: `retention_days` defaults to **30** and every record was under 15 days old, so
it would have reported "0 cleaned" and looked like success. It also runs per-node (93
invocations), handles only `terminated` (not the 21 `error`), and never deletes the `Node`
rows themselves.

Raw `DELETE` was used instead of Rails `destroy`, which is safe **only** because
`System::Node` and `System::NodeInstance` were verified to have no destroy callbacks — so
`dependent: :destroy` was pure FK cascade with no provider-side effects. Deletes were ordered
by FK dependency (certificates → instances → assignments → nodes) inside a transaction, so
any unenumerated dependent would have rolled the whole thing back rather than half-deleting.
A dry run with `ROLLBACK` confirmed the exact counts first.

## Defect 1 (FIXED) — teardown leaves records in `error`, not `terminated`

**20 of the 21 `error` instances had `pool_state = draining`.** Only one was `errored`.
For contrast, the terminated population splits 61 draining / 11 errored.

So this is not provisioning failing. Instances entering the drain path end up with
`status = error` while `pool_state` stays `draining` — a teardown/accounting failure, and it
is ongoing: 10 of the 21 were created in the 7 days before cleanup.

Worth noting for whoever picks this up: there were **zero** `System::Task` rows attached to
any of these nodes, so the error carries no recorded reason anywhere. That absence is itself
a diagnostic gap — a drain that fails should leave a trail.

### Root cause and fix

`ProvisioningService.terminate_instance` **returns** a `Runtime::Result` and only re-raises
`ArgumentError` — a provider failure comes back as an err Result, not an exception. All three
call sites in `InstancePoolService` (`drain!`, and both recycle paths) wrapped it in
`rescue StandardError` and **discarded the return value**, so a failed terminate was
indistinguishable from a success: drain logged `ready_terminated=N`, the VM kept running, and
the row sat non-terminal until `Fleet::DecisionEngine#reap_presumed_dead!` flipped it to
`status=error` on heartbeat silence. That is the exact `draining` + `error` pair observed.

Fixed by routing all three sites through a `terminate_member` helper that inspects the
Result, logs at `error`, and returns a boolean. A failed drain now parks the member in
`pool_state=errored` (set directly — `mark_pool_errored!` refuses a `draining` row) and emits
a `system.pool.terminate_failed` FleetEvent, closing the "no trail" gap. `drain!` also
returns a `terminate_failed` count so its success number is honest.

The old happy-path spec had to be corrected: it seeded members with no `cloud_instance_id`,
so the real terminate returned `err("Instance has no cloud instance ID")` and the example
asserted `drained == 2` for two members whose terminates had both failed. It now stubs a
successful terminate.

**Still open, related:** the comment at `recycle_stale_members!` promises "errored members →
terminated (cleanup)", but no such phase exists — a `pool_errored` scope is defined and never
used. Errored members now get pruned eventually via retention, but they are never retried.
A bounded-retry design is an operator decision, so it was left alone.

## Defect 2 (FIXED) — nothing schedules record retention

94 records accumulated in 15 days because no scheduled job runs
`task_resource_cleanup` with `delete_terminated`. This cleanup was a one-off; at the observed
churn the list is back to ~90 stale records within a fortnight.

A fix needs both: a scheduled invocation, and a `retention_days` that matches pool churn
(the 30-day default is longer than a builder's entire lifecycle). Fixing defect 1 would cut
the volume but not the accumulation.

### Fix

Added a `prune_dead_records!` phase to `recycle_stale_members!`, which the worker's
`InstancePoolReplenisherJob` already drives every 60s via the pool's `recycle_stale`
endpoint — so **no new job, schedule entry, or worker change was needed.** It destroys pool
members in a terminal status (`terminated`/`error`) past `DEAD_RECORD_RETENTION_DAYS`
(default 7, overridable per pool via `metadata["record_retention_days"]`, 0 disables), and
removes the member's Node once its last instance is gone — guarded on there being no
surviving instances, so a shared or pre-provisioned Node is never taken out from under a live
one. Scoped through `pool.node_instances` (`instance_pool_id`), so it can only ever touch
that pool's own members. Uses `destroy` rather than `delete_all` for the same NO ACTION FK
reason as the manual cleanup. Reported as `records_pruned` in the tick's counts.

It runs outside the tick's `FOR UPDATE` transaction: it only touches rows already dead and
past the window, so it never contends with `acquire!`/`drain!`, and holding pool row locks
across a cascading destroy would serialise the 60s tick behind it.

## Reproducing the census

```sql
SELECT status, count(*), min(created_at)::date, max(created_at)::date
FROM system_node_instances
WHERE name LIKE 'ci-native-builder%'
GROUP BY status ORDER BY count(*) DESC;
```

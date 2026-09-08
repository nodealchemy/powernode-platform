# ops-hub as golden origin — direction of record (2026-09-08)

**Status**: operator rulings recorded; four campaign proposals filed; three existing proposals
approved and spawned; prune of the control plane authorised but blocked on a grant.
**Scope**: our own deployments (dev, ops, and the future prod). Other operators build their own
infrastructure with the platform; nothing here is deployment policy for them.

## Goal (restated)

The ops hub is the single source of truth from which every other managed resource — the dev
cell, CI builders, test fabrics and, soon, production — is designed, built, deployed, migrated
and retired. Agents on the hub hold live knowledge of all running infrastructure and have the
wherewithal to act on it with minimal human intervention. The platform stays the ideal
orchestration substrate for AI/MCP workloads: intent in, running resources out.

## Operator rulings

| Question | Ruling |
|---|---|
| Prune scope | Everything dead: terminated/error/stopped CI-builder rows, the Aug-9 ops-cell experiments, the stuck ops-cell. Keep the hub, the dev cell, the live builders, and the SDWAN testbed pending the fabric campaign. |
| Demo seed content | Delete from the hub (business demo agents, demo templates/modules, the local-qemu provider). Seeds stay in the repo; demo content becomes opt-in. |
| Production topology | **Federated child plane** spawned by the hub via `managed_child`; the hub is the origin. |
| Production substrate | Same hypervisor as the hub for now; relocate later via storage migration + VIP. |
| Production shape | Monolithic hub first; per-component decomposition over SDWAN later (north star). |
| Autonomy default | Trusted for reversible actions; approval for destructive ones and for anything touching a control-plane node or prod. |
| Infrastructure knowledge | All of: live inventory in the knowledge graph, standing agent duties, change records + per-project runbooks, on-demand query verbs. Keep model context small; discover relevant verbs proactively. |
| Verb discovery | Tool families + lazy describe; per-agent narrow grants; route_task-first with context hints; compressed inventory digests. |
| Front door | Brief → Project → Architecture → Provision (→ Operate → Retire). |
| Packaging | Four campaign proposals plus individual improvements in dev-improve. |
| Legacy support | **None.** Legacy, back-compat, grandfathered and deprecated paths are deleted when discovered and callers migrated; no shims, no default-on compat toggles. Recall `search_knowledge tag:guidance-no-legacy-support`. |

## Campaigns

Approved and spawned this session (pre-existing proposals):
- A project owns its template and declares its modules, and its lifecycle stops meaning nothing.
- No bare facts: every returned name carries its scope and every value its basis.
- SDWAN test fabric: every advertised network capability observable on real VMs.

Proposed and approved this session (spawned as campaigns), in drive order:
1. **Environment as a first-class noun** — dev/ops/staging/prod/ci with per-environment policy,
   blast radius and promotion ladder.
2. **Agents that know the fleet** — inventory reconciler + digests, `Ai::AgentDuty` + tick job,
   change records, tool-family verb discovery, hygiene lanes (dead-node reaper, catalog hygiene).
3. **Federated production plane** — the hub spawns and governs a `managed_child` prod hub; child
   pulls catalog, origin pulls telemetry; cross-environment promotion; DR drill.
4. **One front door** — brief → project → architecture → provision → operate → retire.

Rejected/parked: the proving-ground campaign stays proposed (depends on the SDWAN fabric).

## Individual improvements queued to dev-improve

- Pool recycle orphans Node rows; add producer fix + gated dead-node reaper.
- Demo seed content is unconditional; make it opt-in with a removal verb.
- No governed SiteSetting write verb (INV-1 cannot be armed without break-glass).
- Operator seat's instance grant lacks delete/reap verbs; derive grants from duty profiles.
- `system_list_instances` has no status filter.
- No governed out-of-band exec path.
- Four monitoring agents overlap; consolidate into one Platform Health Monitor.
- Unconfigured canonical agents export identical 255-tool allowlists.
- SessionStart digest advertises ungranted verbs.

Legacy removals queued under the no-legacy rule:
- FederationGrant raw-PK `fg-` token path and its env toggle; blank scope lists become deny.
- `AuditActions::LEGACY_ACTIONS`; writers migrated, historical rows renamed.
- Ralph loop dormant `learnings` column and its read-union; drained then dropped.
- `core-purity-baseline.txt` burned down to zero and deleted.
- Deprecated `ui/TabContainer` + `ui/TabNavigation`; dead worker_api task actions; serializer legacy fields; positional `api_response` compat; deprecated `syncRepositories`.

## Prune ledger

Counts and identifiers live in the gitignored `docs/operations/local/` ledger. Ruling: no manual prune; it is
executed by the dead-node reaper and catalog-hygiene lanes once the grant-profile and reaper improvements land;
the instance principal correctly refuses to widen its own grant. Module and template deletion
is unblocked on evidence: every candidate has zero assignments and zero nodes, except the
ops-cell template (freed once its experiment nodes are deleted).

# RCP v2 — P0-c invariant enforcement + fleet audit (2026-07-23)

**Campaign:** Resilient Control Plane (RCP) v2 — `campaign_id 019f9250-a199-7819-ace6-cee904116b3e`
**Task:** `p0c-enforce-audit-invariants`
**Scope:** provisioning-time enforcement for INV-1 (no self-management), INV-2 (no boot-time
network dependency), INV-6 (member storage = local disk, no shared NFS root) + a fleet-wide scan
+ this shared-fate audit. Design reference:
`~/.claude/plans/campaign-reciprocal-control-plane.md`.

This is a **report + a scan snapshot**, not a remediation — per this increment's charter, nothing
here changes behavior on any currently-running node. Findings that imply a live fix are named and
routed to the operator, not auto-applied.

> **Update, same day, after live infrastructure access was granted mid-task:** the initial version
> of this audit (below) drew INV-6's "no violation" conclusion from the platform's own
> provisioning-record metadata alone, without live PVE access, and **that conclusion was wrong**.
> Direct, live, read-only queries against dna/rna (via `ssh admin@dna` + root cluster-trust to rna,
> granted by the operator after the initial audit was written) found: (1) `dna-data` is a PVE
> storage of **type `nfs`** (a self-hosted NFS re-export of a dataset under dna's own `local-zfs`
> zpool), not the local `zfspool`-type storage the earlier text assumed — a genuinely-local
> alternative (`zfspool: local-data`) exists on dna and was NOT what ops-hub's VM was built on; (2)
> ops-hub's actual running VM 104 config (`qm config 104`) confirms its root disk, EFI disk, AND
> cloud-init drive are all on `dna-data` — i.e. **INV-6 is not just a theoretical risk, it is a live,
> confirmed violation on the currently-running control-plane VM**; (3) rna's storage independence is
> now definitively confirmed (own section below). The INV-2 and INV-6 sections below are corrected
> in place; corrections are marked. Nothing was fixed live as part of this correction pass except
> the one operator-approved action documented in "Approved action taken" — everything else remains
> report-only.

## What was built

| Concern | File |
|---|---|
| INV-1 fence (no self-management) | `extensions/system/server/app/services/system/autonomy/self_management_fence.rb` |
| INV-2 check (no boot-time network dependency) | `extensions/system/server/app/services/system/autonomy/boot_path_invariant_check.rb` |
| INV-6 check (storage locality) | `extensions/system/server/app/services/system/autonomy/storage_locality_check.rb` |
| Fleet-wide scan (all three) | `extensions/system/server/app/services/system/compliance/rcp_invariant_scanner.rb` |
| Wired into provisioning | `extensions/system/server/app/services/system/provisioning_service.rb` (`provision_instance`, `terminate_instance`) |
| Wired into the fleet reconciler | `extensions/system/server/app/services/system/fleet/decision_engine.rb` (all 6 reap/actuate paths) |
| Wired into compliance reporting | `extensions/system/server/app/services/system/compliance/compliance_snapshot_service.rb` (`rcp_invariants` key) |
| Small behavior-preserving refactor | `extensions/system/server/app/services/system/providers/proxmox_provider.rb` (`cidata_iso_transport?` now delegates to a new public class method `.cidata_iso_transport_for?`, reused by the INV-2 check — no duplicated transport-detection logic) |
| Live verification entry points | `extensions/system/server/lib/tasks/rcp_invariants.rake` (`rcp:invariant_scan`, `rcp:storage_topology`) |
| Specs | one file per new class/module + additions to `provisioning_service_spec.rb`, `decision_engine_spec.rb`, `proxmox_provider_spec.rb` — 246 examples across the touched files, all passing; `scripts/validate.sh --skip-tests --skip-ts` (pattern-validation + gitleaks) also passes clean |

All three checks are **nil-safe / inert by default** — zero behavior change on any currently-running
node until an operator explicitly configures the relevant SiteSetting or passes the relevant opt-in
option. This mirrors the existing `ControlPlaneFence`'s own proven-safe posture.

## Relationship to the existing ControlPlaneFence (campaign 019f71dc)

Read `System::Autonomy::ControlPlaneFence`
(`extensions/system/server/app/services/system/autonomy/control_plane_fence.rb`) and its 6
call sites in `decision_engine.rb` + 1 in `instance_status_sensor.rb` before writing anything —
per this task's instructions. Conclusion: **a distinct fence, not an extension of that one**, for
three concrete reasons:

1. **Different question.** `ControlPlaneFence` answers *"does a DIFFERENT control-plane deployment
   own this instance"* — cross-plane arbitration keyed on a per-instance ownership stamp
   (`NodeInstance.config["control_plane_id"]`) that task #14 (out of scope here, explicitly not
   touched) populates. `SelfManagementFence` answers *"IS this the node hosting ME"* — a single
   deployment's own reflexive identity, keyed on a **different** SiteSetting
   (`self_hosting_node_id`). A plane can legally **own** (per `ControlPlaneFence`) the very instance
   that hosts it — post-cutover, ops-hub's own plane will legitimately be stamped as the owner of
   its own instance — and that is *exactly* the case INV-1 forbids. Hanging INV-1 off
   `control_plane_id` would make INV-1 inert precisely when it matters (today, pre-cutover,
   single-plane) and would conflate two orthogonal questions.
2. **Different activation lifecycle, same discipline.** Both fences are SiteSetting-driven and
   inert-by-default; both should stay that way until an operator deliberately activates them. This
   task does **not** set `self_hosting_node_id` on any live deployment, for the same reason it must
   not flip `control_plane_id` live: activation is an operator/onboarding decision (see "Flagged for
   the operator" below).
3. **Same seam, reused.** `SelfManagementFence` lives in the same `System::Autonomy` namespace, uses
   the same pattern (memoized SiteSetting self-id, nil-safe predicate + a relation/skip helper), and
   is wired into the exact same integration points `ControlPlaneFence` already uses
   (`ProvisioningService#provision_instance`/`#terminate_instance`, and all 6 of
   `DecisionEngine`'s reap/actuate paths, checked immediately alongside the existing fence line).
   `instance_status_sensor.rb` was deliberately **not** touched for INV-1: unlike cross-plane noise
   suppression, a self-hosted instance going silent should still surface as a signal (for external
   observability) — only the automatic *reap* action is fenced, in `reap_presumed_dead!`.

## Fleet-wide scan — CURRENT findings

Three evidence sources were used: (a) direct MCP queries against the live platform (this session is
connected to **dev**'s backend — the sole control plane today, per `campaign-reciprocal-control-
plane.md`'s "Campaign on dev until P7 retires dev"); (b) the new `RcpInvariantScanner`'s logic,
verified correct against 15 passing specs but not run in `live: true` mode from this session (no
Proxmox credentials are wired into the Rails app from this sandboxed worktree); and (c), added
mid-task once the operator granted direct infrastructure access, **live read-only SSH queries
against dna/rna themselves** (`zpool list`, `/etc/pve/storage.cfg`, `qm config 104`,
`/etc/pve/corosync.conf`, `smartctl`) — these are the most authoritative source where they apply
and are cited explicitly below.

### INV-1 (no self-management)

**No violation found — and the check is currently a no-op on dev.** `self_hosting_node_id` is
unset (confirmed: no SiteSetting query for it was ever populated), so `SelfManagementFence` is
fully inert on dev today — which is correct, because **dev is not itself a Powernode-managed
node** (it is a plain workstation the platform happens to run on, not a `System::Node`/
`NodeInstance` row dev manages). There is nothing for dev to self-manage.

**Blind spot, stated plainly:** this audit has MCP access to dev's backend only. If ops-hub is
already running its **own**, separate instance of the Powernode backend (a second, distinct
database) — which is the entire premise of the "ops-hub is its own control plane" incident history
this campaign traces to — this session has **no visibility into that plane's own Node/NodeInstance
table** to check whether *it* has a self-referential row. That check can only be run **from
ops-hub's own backend context**, once (and if) `self_hosting_node_id` is set there. This is squarely
task #14 / the P1-a onboarding territory, not something this increment can see or fix.

### INV-2 (no boot-time network dependency)

**CONFIRMED LIVE, with the exact NFS export pinned down (corrected/sharpened after live access).**

- The live Proxmox provider (`IPNode-PVE`, id `019e446f-916c-75d2-8f4d-b44bf7cb8664`, endpoint
  `https://dna.ipnode.net:8006`) has **no `cidata_transport` key** in its `System::Provider#config`
  (confirmed via `system_list_providers`).
- `ProxmoxProvider#stage_cicustom`'s own doc comment states the default assumption explicitly:
  *"Defaults assume the Powernode-platform-on-ops shape: dsm-data NFS at
  /mnt/pve-data/snippets"*.
- **Live-confirmed via `qm config 104` on dna:** ops-hub's actual VM config carries
  `cicustom: user=dsm-data:snippets/104-user.yml,meta=dsm-data:snippets/104-meta.yml` — the
  cicustom snippets specifically ride **`dsm-data`**, an NFS export from the Synology
  (`dsm.ipnode.net:/volume1/Data`, per `/etc/pve/storage.cfg`), matching the code's documented
  default exactly. This pins the earlier (correct but less precise) finding down to the exact host.
- Net: **ops-hub's boot-time cloud-init / federation-payload identity delivery depends on the
  NFS-backed cicustom snippets channel (`dsm-data`) being reachable at boot** — confirmed live, not
  just inferred.
- **Residual gap, still real:** `cidata_transport` is read from the `System::ProviderConnection`'s
  own config, not the parent `Provider`'s. No MCP tool surfaces `ProviderConnection#config`
  directly (confirmed by a thorough tool search — see "Approved action taken" below), so whether the
  live *connection* (as opposed to the Provider row) already carries an override could still not be
  read directly — though the live `qm config 104` evidence above makes this moot for ops-hub
  specifically: whatever the connection's current config is, VM 104 was built using the cicustom/NFS
  path, not the ISO transport.

### INV-6 (member storage = local disk, no shared NFS root)

**RETRACTION: the original version of this section concluded "no violation found." That was
wrong** — it inferred "dna-data is local ZFS" from the campaign design doc's own paraphrase +
provisioning metadata, without checking the actual PVE storage *type*. Live access corrected this:

**`/etc/pve/storage.cfg` on dna (full listing, live) shows `dna-data` is `nfs`-type, NOT
`zfspool`-type:**
```
zfspool: local-data
	pool local-zfs/local-data
	content images,rootdir
	mountpoint /local-zfs/local-data

nfs: dna-data
	export /local-zfs/dna-data
	path /mnt/pve/dna-data
	server dna.ipnode.net
	content vztmpl,iso,images,snippets,rootdir,import
```
`dna-data` is a **self-hosted NFS re-export** of a dataset carved out of dna's own `local-zfs`
zpool (`local-zfs/dna-data`) — served over NFS (even to dna itself) so every cluster node can see
identical content. A genuinely local, non-NFS alternative already exists on the same host:
`zfspool: local-data` (backed directly by `local-zfs/local-data`, no NFS layer at all).

**CONFIRMED LIVE VIOLATION, not a candidate:** `qm config 104` on dna (ops-hub's actual, currently
running VM) shows:
```
scsi0: dna-data:104/vm-104-disk-0.raw,discard=on,iothread=1,size=160G     <- ROOT DISK
efidisk0: dna-data:104/vm-104-disk-0.qcow2,efitype=4m,size=528K            <- EFI/bootloader disk
ide2: dna-data:104/vm-104-cloudinit.qcow2,media=cdrom                      <- cloud-init seed drive
```
**ops-hub's root disk, EFI disk, and cloud-init drive are all on `dna-data` — the NFS-type
storage — right now, on the live, running VM.** This is a materially bigger finding than the
original INV-2-only characterization: it means ops-hub's disk I/O for its *actual root filesystem*
rides a self-hosted NFS re-export of dna's zpool, not a direct local `zfspool` PVE storage. A hang
or crash in dna's own NFS server daemon (independent of the underlying zpool's health) could stall
ops-hub's root filesystem I/O — a strictly worse failure mode than a native `zfspool`-type storage
would have, and exactly the class of hazard INV-6's "no shared NFS for member root disks" text is
written to forbid. The underlying *bytes* being on dna's own disks (not truly remote) does not
satisfy INV-6 — the PVE storage *type* is what matters, and it is `nfs`. **Not fixed here** — this
was discovered during this correction pass and is a new, more urgent item for "Flagged for the
operator" below; changing a running VM's root-disk backend is a live storage migration, categorically
more invasive than the one narrowly-scoped, approved action this task took (see below), and was not
attempted.

**rna's `local-data` zpool independence — NOW DEFINITIVELY CONFIRMED, not just inferred.**
Independently verified (not merely relayed) via live, read-only queries:
- `sudo zpool list` on dna: pool `local-zfs`, **14.5T**.
- `sudo ssh rna zpool list` (root cluster-trust, dna → rna): pool `local-zfs`, **3.62T** — same
  *name* (Proxmox's conventional default), but a **different pool** — sizes differ by 4x, and:
- `sudo ssh rna smartctl -i /dev/disk/by-id/ata-ST4000VN008-2DR166_ZGY9R1DG`: a physical 4TB
  Seagate IronWolf (`ST4000VN008-2DR166`, serial `ZGY9R1DG`) — confirmed distinct physical hardware
  from dna's pool. **Closed**: rna's storage is an independent failure domain from dna's, on
  distinct physical disks. (No instance is placed on rna today — P1-a hasn't happened — so this is
  pre-flight confirmation for that future increment, not a current violation finding one way or the
  other.)

**Documentation note (not a bug):** `proxmox_provider_spec.rb`'s existing `#list_volume_types` test
fabricates a fixture entry named `"dna-data"` with `plugintype: "nfs"` purely to exercise the
method's response-parsing logic — a comment was added there. In an odd twist, that fixture's
`"nfs"` plugintype turned out to match the REAL dna-data's real type after all (the comment has
been left in place since it's still correct that the fixture was arbitrary test data, not a claim,
at the time it was written — the audit itself is what independently established the real type).

## Shared-fate audit — residual correlated failure domains

Per INV-6's own text, name honestly what a single-site deployment **cannot** eliminate, even after
P1 (ops-hub-B on rna) lands:

1. **Shared switch.** dna and rna (and every other fleet host) hang off the same physical network
   fabric today. A switch failure (or a misconfigured VLAN/firewall rule taking the segment down)
   is correlated across every member regardless of which zpool or which PVE node they're on.
2. **Site power.** Same electrical circuit/UPS domain. A power event takes dna, rna, and the switch
   down together — no storage or compute redundancy addresses this on one site.
3. **The PVE corosync quorum itself.** The cluster is **4 nodes** (confirmed live via
   `/etc/pve/corosync.conf`): `dna` (nodeid 1, `quorum_votes: 2`), `fna` (nodeid 2, 1 vote), `lna`
   (nodeid 3, 1 vote), `rna` (nodeid 4, 1 vote) — **5 total votes, with dna double-weighted**.
   **Confirmed: there is currently no QDevice configured** — no `device { }` block exists in
   corosync.conf at all. This is exactly the shared substrate RCP's P1 design *relies on* to
   arbitrate life/death, and today it has no independent witness — dna's own double vote-weight
   means dna alone is much closer to a quorum-deciding position than a peer, the opposite of the
   arbitration RCP wants. This is precisely why the design doc requires a QDevice witness in a
   **third, independent** failure domain, and confirms P1-b's witness work is a real, entirely
   unstarted gap, not a paper requirement — this increment does not implement it (P1-b's job), only
   confirms it's still open.
4. **The NFS/snippets server itself (`dsm.ipnode.net`, Synology) — a fourth domain surfaced by this
   investigation, not named explicitly in the original three.** It backs BOTH the one tracked
   `ProviderVolume` (`dsm-powernode`) AND (per the INV-2 finding above) the cicustom snippets
   channel used for cloud-init/federation payload delivery. Today it is a single shared dependency
   that, if down, can affect boot-time payload delivery for *any* Proxmox-provisioned instance using
   the default (non-ISO) transport, regardless of which PVE node/zpool that instance's root disk
   lives on. This is a distinct correlated-failure axis from "which zpool is my root disk on" and is
   not resolved by INV-6's local-storage requirement alone — it is resolved by INV-2 (moving off the
   NFS cicustom channel).

None of these four are "bugs" to fix in this increment — they are the honest limits of a two-site
(dna/rna), one-switch, one-circuit homelab topology. The design doc's own P7 ("shrink the anchor")
and the witness-in-a-third-domain requirement (INV-7) are the acknowledged, deliberate mitigations;
a genuine third physical site is the only way to fully retire #1–#3.

## Approved action taken — INV-2 `cidata_transport: iso` (attempted, blocked on tooling)

Operator/coordinator approved, after reviewing the INV-2 finding, setting `cidata_transport: "iso"`
on the live `IPNode-PVE` provider **connection** going forward, scoped narrowly to that one config
key.

**Blast-radius analysis (completed, high confidence):**
- `cidata_iso_transport?`/`stage_cicustom` vs. `stage_cidata_iso` are consulted **only inside
  `create_instance`** at VM-creation time (`POST /api2/json/nodes/<node>/qemu` body construction) —
  never re-evaluated afterward.
- A graceful or forced reboot (`ProxmoxProvider#reboot_instance`) does **not** touch the cloud-init
  drive at all (PVE's own `qmreboot` never reloads the cloudinit seed — confirmed by an existing
  code comment in `reboot_instance`).
- The only code path that *would* re-materialize a VM's cloud-init seed post-creation,
  `reload_cloudinit_seed!` (invoked only via the public `power_cycle_instance`), is called from
  exactly one place: `System::InstancePoolService#reload_pending_seeds!` — a **pool-reaper**
  mechanism that retries only for **warming, not-yet-enrolled pool members**. ops-hub is a
  standalone provisioned VM, not an instance-pool member, so this path never touches it.
- **Conclusion: this change has ZERO effect on VM 104 (ops-hub) — not immediately, not on its next
  reboot, not ever, short of someone manually rebuilding/re-provisioning it.** It affects only
  **future** `create_instance` calls through this connection (new VMs, uefi_disk/direct_kernel boot
  mode, with a payload to deliver) — those will use the ISO transport (`stage_cidata_iso`, an
  in-process-built NoCloud ISO uploaded via the PVE storage API and attached as a CD-ROM) instead of
  writing snippet files to NFS.

**Applying it — blocked, not attempted further.** The value lives on `System::ProviderConnection#
config` (confirmed via `BaseProvider#initialize`'s `@connection` — a `ProviderConnection`, not a
`Provider` — and `Providers::Registry#find_connection_for_region`/`#find_connection_for_instance`,
which query `System::ProviderConnection` directly), **not** `System::Provider#config`. A thorough
search of the available MCP tool surface found:
- `system_get_provider` / `system_update_provider` — operate on `System::Provider` only. Writing
  `cidata_transport` there would be silently ineffective: `cidata_iso_transport?` reads
  *only* the connection's own config, with no Provider-level fallback (unlike `default_storage`,
  which does fall back — see the `pve_credential` note in this increment's code comments).
- `system_create_provider_connection` — creates a **new, separate** `ProviderConnection` row; it
  does not update the existing one, doesn't accept credentials directly (resolves them from Vault
  at use time), and having two `status: "connected"` rows for the same provider+account makes
  `find_connection_for_region`'s "first connected" resolution order-dependent/non-deterministic —
  a materially different and riskier action than "change one field on the existing row," and not
  attempted.
- No generic settings/config MCP tool, and no `list`/`get`/`update_provider_connection` tool exists.
- `rails runner`/console access from this session is not available: this agent is sandboxed to its
  worktree, and every attempt this session to run a command against `/opt/powernode` (the live
  checkout, where credentials decrypt) was refused by the tool layer itself (confirmed repeatedly,
  not merely assumed from the "worktree credential decrypt empty" operational note).

**Net: the approved action was not applied — not because it's unsafe (the blast-radius analysis
above shows it is safe and correctly scoped), but because no tool available to this session can
write `System::ProviderConnection#config` for an existing row, and creating a new row instead is a
materially different, riskier action this task did not take.** What's needed to close this: either
(a) an MCP tool (or a rails-console-capable session, run from `/opt/powernode/server`) that can
update the existing `ProviderConnection` for provider `019e446f-916c-75d2-8f4d-b44bf7cb8664`
("IPNode-PVE") — merge `{"cidata_transport" => "iso"}` into its `config` — or (b) explicit
authorization to create a replacement connection understanding the resolution-order risk above.

## Flagged for the operator (decisions/actions, not made here)

1. **`self_hosting_node_id` is not set anywhere** (mirrors `control_plane_id`'s own dormancy). Until
   an operator sets it on ops-hub's own (future, separate) backend deployment, `SelfManagementFence`
   is a correct but inert safety rail there. Recommend pairing this with task #14's runbook — both
   are "tell this deployment who/what it is" onboarding steps.
2. **NEW, most urgent finding of this correction pass: ops-hub's root disk, EFI disk, and cloud-init
   drive are confirmed LIVE on `dna-data` (NFS-type storage), not a local `zfspool`** — see the
   corrected INV-6 section above. A genuinely-local alternative (`zfspool: local-data`) already
   exists on dna. Moving ops-hub's root disk to it is a live storage migration (categorically more
   invasive than the approved cidata-transport change) and was **not attempted** — this needs an
   explicit operator decision on timing/method (likely coupled to P1's "cattle, not pets" rebuild
   philosophy rather than an in-place migration).
3. **INV-2's remediation (cidata ISO transport) was approved but could not be applied** — see
   "Approved action taken" above. Needs either a new MCP tool/capability or a differently-privileged
   session to complete. The new `options[:rcp_member_provisioning]` strict gate in
   `ProvisioningService` will enforce this for **future** RCP-member provisions (P1-a/P1-d)
   regardless.
4. **No QDevice configured today** (confirmed live via corosync.conf) — P1-b's witness work is a
   real, unstarted gap; dna currently carries double quorum weight with no independent tie-breaker.
5. **This audit's scan coverage is dev-plane-only** (see the INV-1 blind spot above) — it cannot see
   whether ops-hub's own (if any) separate backend deployment has any self-referential fleet rows.

## Verification

- 246 RSpec examples across all new/modified files, 0 failures (run individually per file from
  `/opt/powernode/.claude/worktrees/agent-a3605674b61f82061/server` against an isolated worktree
  test DB — `powernode_test_agent_a3605674b61f82061`).
- `scripts/validate.sh --skip-tests --skip-ts`: pattern-validation 43/43 PASS, gitleaks 0 leaks.
- No live node's behavior changed as a result of the code in this increment — every new check is
  nil-safe/opt-in by default; nothing in the code changes sets a SiteSetting or mutates any live
  provider/connection config. The live, read-only infrastructure queries run directly against
  dna/rna during this correction pass (zpool list, storage.cfg, qm config, corosync.conf, smartctl)
  were all read-only; the one approved write (INV-2 cidata_transport) was not applied, per above.

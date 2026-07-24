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

Two evidence sources were used: (a) direct MCP queries against the live platform (this session is
connected to **dev**'s backend — the sole control plane today, per `campaign-reciprocal-control-
plane.md`'s "Campaign on dev until P7 retires dev"), and (b) the new `RcpInvariantScanner`'s logic,
verified correct against 15 passing specs but **not executed live** from this session (see
"Verification gaps" — this worktree has no Proxmox credentials).

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

**A real, currently-live violation candidate, confirmed via the platform's own provisioning
records + the provider adapter's own code:**

- The live Proxmox provider (`IPNode-PVE`, id `019e446f-916c-75d2-8f4d-b44bf7cb8664`, endpoint
  `https://dna.ipnode.net:8006`) has **no `cidata_transport` key** in its `System::Provider#config`
  (confirmed via `system_list_providers`).
- `ProxmoxProvider#stage_cicustom`'s own doc comment states the default assumption explicitly:
  *"Defaults assume the Powernode-platform-on-ops shape: dsm-data NFS at
  /mnt/pve-data/snippets"* — i.e. the code itself documents that ops-hub's shape is the NFS-cicustom
  default.
- ops-hub's currently-running instance (`019f680e-d4ff-7f17-943b-ed31eb3be8da`) has
  `cloud_instance_id: "dna/qemu/104"` — confirming it boots via this exact Proxmox connection.
- Net: **ops-hub's boot-time cloud-init / federation-payload identity delivery depends on the
  NFS-backed cicustom snippets channel being reachable at boot** — the frozen-LKG-adjacent hazard
  this whole campaign traces to, and a textbook INV-2 violation (boot-critical path depends on
  network/NFS).
- **Residual gap:** `cidata_transport` is actually read from the `System::ProviderConnection`'s own
  config, not the parent `Provider`'s (see "config resolution" note in
  `boot_path_invariant_check.rb`) — no MCP tool surfaces `ProviderConnection#config` directly, so
  this finding is corroborated (Provider-level absence + the code's own explicit framing + the
  prior `ops-hub-cicustom-needs-nfs-snippets` operational memory) but **not independently
  reconfirmed at the connection level** from this session. Run `rails rcp:invariant_scan` from a
  live context (`/opt/powernode/server`, not a worktree) for the fully authoritative answer — the
  scanner resolves through `Providers::Registry.for_instance` down to the actual connection.
- **Not fixed here.** The remediation (setting `cidata_transport: "iso"` on the live connection, or
  moving to the ISO transport) is a live-behavior change to a currently-functioning boot path and is
  explicitly out of scope for this increment (flagged below).

### INV-6 (member storage = local disk, no shared NFS root)

**dna-data confirmed local (re-derived, not assumed):** the live `IPNode-PVE` provider's
`default_node: "dna"` + `default_storage: "dna-data"`, combined with ops-hub's own
`cloud_instance_id: "dna/qemu/104"`, independently corroborates the established fact that
`dna-data` is dna's own local storage — the same single point of failure that took ops-hub down
once (per `ops-hub-cannot-self-provision-egress-blocks-proxmox` / this campaign's own "Why").

**rna's `local-data` zpool independence — NOT independently re-verified.** This audit was asked to
confirm this "rather than assuming it from memory." A genuine attempt was made and fell short of a
live answer:
- No SSH access from this sandboxed worktree to `dna.ipnode.net` / `rna.ipnode.net` (tried
  `admin@`/`rett@`, both `Permission denied (publickey,password)` — no credentialed path available
  to this session, by design).
- No MCP tool exposes raw Proxmox `storage.cfg` (`list_volume_types` is a `ProxmoxProvider`
  instance method requiring live credentials, not an MCP action).
- The platform's own `System::ProviderVolume` table has exactly one row (`dsm-powernode`, NFS,
  unattached) — unrelated to the dna/rna PVE-cluster-local storage question.
- **This is why `rails rcp:storage_topology[<node>,rna]` was built** (reuses the existing,
  already-live `ProxmoxProvider#list_volume_types` — no new PVE API code): run it from
  `/opt/powernode/server` (real credentials) to get the authoritative plugin_type/shared answer for
  every pool visible on `rna`, closing this gap before/alongside P1-a ("ops-hub-B on rna").
- No currently-running instance is placed on rna today (P1-a hasn't happened yet), so there is no
  live INV-6 finding to report for rna one way or the other — this is a **pre-flight verification
  gap**, not a detected violation.

**Documentation note (not a bug):** `proxmox_provider_spec.rb`'s existing `#list_volume_types` test
fabricates a fixture entry named `"dna-data"` with `plugintype: "nfs"` purely to exercise the
method's response-parsing logic. A comment was added at that test to head off a future reader
mistaking that arbitrary test double for a claim about the real deployment's dna-data (confirmed
above to be local ZFS, not NFS).

## Shared-fate audit — residual correlated failure domains

Per INV-6's own text, name honestly what a single-site deployment **cannot** eliminate, even after
P1 (ops-hub-B on rna) lands:

1. **Shared switch.** dna and rna (and every other fleet host) hang off the same physical network
   fabric today. A switch failure (or a misconfigured VLAN/firewall rule taking the segment down)
   is correlated across every member regardless of which zpool or which PVE node they're on.
2. **Site power.** Same electrical circuit/UPS domain. A power event takes dna, rna, and the switch
   down together — no storage or compute redundancy addresses this on one site.
3. **The PVE corosync quorum itself.** dna + rna are members of one Proxmox cluster; the
   corosync/QDevice quorum layer that RCP's own P1 design *relies on* to arbitrate life/death is
   itself a shared substrate. A corosync-level split-brain or a cluster-wide config error is a
   single failure mode that can affect every member simultaneously — this is exactly why the design
   doc requires the QDevice witness to sit in a **third, independent** failure domain, and why P1-b's
   gate is a demonstrated partition test, not a paper design.
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

## Flagged for the operator (decisions/actions, not made here)

1. **`self_hosting_node_id` is not set anywhere** (mirrors `control_plane_id`'s own dormancy). Until
   an operator sets it on ops-hub's own (future, separate) backend deployment, `SelfManagementFence`
   is a correct but inert safety rail there. Recommend pairing this with task #14's runbook — both
   are "tell this deployment who/what it is" onboarding steps.
2. **INV-2's remediation (cidata ISO transport) was found but not applied.** Setting
   `cidata_transport: "iso"` on the live `IPNode-PVE` connection (or per-node override) would fix
   the NFS boot-dependency, but is a live behavior change to a currently-working boot/federation path
   this increment was told to flag rather than make. The new `options[:rcp_member_provisioning]`
   strict gate in `ProvisioningService` will enforce this for **future** RCP-member provisions
   (P1-a/P1-d) without touching anything already running.
3. **Live verification owed before/alongside P1-a:** run `rails rcp:storage_topology[ops-hub,rna]`
   and `rails rcp:invariant_scan LIVE=1` from `/opt/powernode/server` (real credentials) to (a)
   confirm rna's `local-data` zpool's real PVE plugin_type/shared flag, and (b) get a
   connection-level-accurate INV-2 reading. Both were built specifically because this sandboxed
   session could not reach live infrastructure to do it itself.
4. **This audit's scan coverage is dev-plane-only** (see the INV-1 blind spot above) — it cannot see
   whether ops-hub's own (if any) separate backend deployment has any self-referential fleet rows.

## Verification

- 246 RSpec examples across all new/modified files, 0 failures (run individually per file from
  `/opt/powernode/.claude/worktrees/agent-a3605674b61f82061/server` against an isolated worktree
  test DB — `powernode_test_agent_a3605674b61f82061`).
- `scripts/validate.sh --skip-tests --skip-ts`: pattern-validation 43/43 PASS, gitleaks 0 leaks.
- No live node's behavior changed — every new check is nil-safe/opt-in by default; nothing in this
  increment sets a SiteSetting or mutates any live provider/connection config.

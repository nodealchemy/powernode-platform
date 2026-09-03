# RCP P1-a Design: ops-hub-B on rna/local-data

> **Status: design + prerequisite code fix landed; provisioning itself NOT executed.** Campaign
> `019f9250-a199-7819-ace6-cee904116b3e` ("Resilient Control Plane v2"), increment **P1-a**: *"Stand up
> ops-hub-B on rna/local-data. Acceptance: B healthy, `/up` 200, on rna's independent zpool."*
>
> **2026-07-24 update — operator approved the §2.3 code fix and the VMID/convention in §4.** The 3-line
> `build_provider_params` fix has been **applied and committed** (`extensions/system` commit `9edd004a`,
> parent pointer bump in this worktree — see §2.3), with test coverage proving pinned `vmid`/`storage`/
> `cidata_iso_storage` now reach the adapter and a regression spec proving every existing call shape is
> unchanged (43/43 examples pass). **VMID 9100 and the `9100-9199` "permanent RCP member" block convention
> are approved** — use 9100 for ops-hub-B going forward (§4). **Actual provisioning (creating the
> `ProviderRegion`, the `Node`, or the VM) is still NOT done** — it remains gated on **P0-b's boot-counter
> rollback-proof gate closing** (per the campaign plan: P0's gate must close before P1 executes). Nothing
> in Proxmox or the live DB has been touched; only the two files below (inside `extensions/system`) and
> this document changed.
>
> Off-limits, untouched by this design and by the recon/fix that produced it: VMIDs **9001**
> (P0-a watchdog), **9002** (P0-b throwaway), **104** (ops-hub-A), **105** (opn-1 firewall).

## 0. TL;DR — key decisions

| Question | Decision | Confidence |
|---|---|---|
| Provisioning mechanism | Standard `System::ProvisioningService.provision_instance` (the platform's existing primitive) — **not** hand-rolled `qm`, **not** a new GitOps pipeline | High, code-verified |
| Golden image | Already exists: `NodePlatform` **ubuntu-24.04-amd64-uefi**, currently-published `DiskImagePublication` at git_sha `a60b0a0d4d…`, built 2026-07-19 | High, DB-verified |
| Config-in-git | Already exists: the `powernode-ops-hub` **NodeTemplate**'s 11-module closure, auto-applied to any Node bound to it | High, DB-verified |
| VMID | **9100** (new "9100s = permanent RCP consensus members" block; reserves 9101+ for the P1-b witness) | **Approved by operator 2026-07-24**; verified free in Proxmox + DB |
| PVE node placement | `provider_region_id` → a **new** `ProviderRegion(region_code: "rna")` — this genuinely works today for `uefi_disk` boot mode, no code change needed | High, code-verified |
| Storage placement (`local-data`) | Was blocked by a real code gap — **fix applied and committed** (`extensions/system` `9edd004a`), spec-covered | **Done** — see §2.3 |
| B's role before P1-b | Provision as **standalone** (sovereign: own admin, own DB, own hostname/cert) — explicitly *not* wired into A's data, traffic, or DNS | Recommendation |

---

## 1. Ground truth used (not re-derived)

Per the task brief, treated as given: 4-node PVE cluster (dna .10/fna .11/lna .12/rna .13, no QDevice yet);
rna's `local-data` zfspool (3.62T/~2.85T free) is physically independent from dna's `local-zfs`;
rna already hosts 7 stopped, unrelated legacy VMs (101/103/106/110/112/206/301); ops-hub (104) was just
migrated onto dna's own `local-data`; VMIDs 9001/9002 are spoken for.

## 2. Provisioning mechanism

### 2.1 What I verified in code (this session)

**The params-threading gap is real, and I traced it to the exact lines.**
`System::ProvisioningService#build_provider_params`
(`/opt/powernode/extensions/system/server/app/services/system/provisioning_service.rb:333-412`) builds the
hash passed to the provider adapter's `create_instance`. It threads `options[:hostname]`, `:key_name`,
`:security_groups`, `:subnet_id`, `:network_id`, `:availability_zone`, `:user_data`, `:boot_mode`,
`:root_volume_size/_type`, `:ssh_key`, `:tags` — **but never `options[:vmid]`, `options[:storage]`, or a
string-valued `options[:node]`.** It unconditionally sets `params[:node] = node` (the `System::Node` AR
record), and `Providers::ProxmoxProvider#pve_node_name(params)`
(`proxmox_provider.rb:1751`) only accepts a **String** there — so that key is always non-string coming out
of `build_provider_params`, full stop.

**This is P0-b's discovery, and it still holds** — confirmed independently by reading the current code,
not by trusting the earlier report.

**What I found beyond P0-b's note: the gap is boot-mode-specific for node placement, but universal for
storage/vmid.** `ProxmoxProvider` has *two* VM-creation code paths with different placement logic:

- `create_vm_instance` (boot_mode `cloud_init`, `proxmox_provider.rb:752-845`): node = `pve_node_name(params)
  || first_online_node!(c)` — **no region fallback at all.** A `cloud_init` VM can never be pinned to a
  specific PVE node via the standard call.
- `create_uefi_disk_vm_instance` (boot_mode `uefi_disk`, `proxmox_provider.rb:1263-1375`): node =
  `pve_node_name(params) || region&.region_code.presence || pve_credential("default_node", ...) ||
  first_online_node!(c)`. **This already honors the region** — exactly what the class's own doc comment
  promises ("PVE doesn't have regions; it has cluster nodes. We model each PVE node as a region... since
  node placement matters") but which `create_vm_instance` doesn't deliver on.

  `ops-hub-A's NodeTemplate ("powernode-ops-hub") already has `boot_mode: "uefi_disk"`* (verified via DB,
  §3), which puts B on the *good* path for node placement — **no code fix is needed to pin the PVE node**,
  only a new `ProviderRegion` row (§4).

- **Storage and VMID remain broken for both boot modes.** Neither `create_vm_instance` nor
  `create_uefi_disk_vm_instance` ever reads `options[:storage]`/`options[:vmid]` — both read the bare
  top-level `params[:storage]`/`params[:vmid]`, which `build_provider_params` never populates from
  `options`. Confirmed no caller anywhere in the tree (`agent_fleet_mission_service.rb`,
  `system_fleet_tool.rb`, `federation/spawn_provisioner.rb`, `platform_deployment_orchestrator.rb`,
  `instance_pool_service.rb`, `provision_full_stack_executor.rb`, `nodes_controller.rb` — every real caller
  of `ProvisioningService.provision_instance`, via `grep`) ever threads `vmid:`/`storage:` through
  `options`. **Nobody has ever exercised this path** — it's not "P0-b called it wrong," it's a genuine,
  unexercised gap.

  Even with node placement fixed, storage would **still** auto-select the wrong pool:
  `first_shared_storage_with_content!` (`proxmox_provider.rb:1756`) requires `shared==1` (or "only one
  storage on the node"). rna's `local-data` is a `zfspool` with `content images,rootdir` and no `shared`
  flag (defaults `0`, and `pvesm status`/`storage.cfg` confirm it, per §1) — auto-selection will land on a
  `shared==1` NFS pool (`dna-data` or `dsm-data`), never on `local-data`, independent of the node bug.

- **Checked for collateral damage**: `params[:storage]`/`params[:vmid]` are read **only** by
  `proxmox_provider.rb` (`grep` across every provider adapter file returned zero hits in
  AWS/GCP/Azure/OpenStack/LocalQemu/Mock/ProCloud) — the shared `build_provider_params` helper is safe to
  extend for these two keys with no effect on any other provider or any existing caller that doesn't pass
  them.

### 2.2 A nuance I found beyond the brief: `cidata_transport`

The single existing Proxmox `ProviderConnection` (`019f373f-27ee-...`) has `config["cidata_transport"] =
"iso"` **today** — this is more recent than ops-hub-A's own creation (its live `cicustom:` line
references `dsm-data:snippets/...`, the *older* NFS-snippet transport; the connection was hardened to
`iso` transport at some point after). Practically: **a fresh provision through this connection today
already avoids the NFS-at-create-time dependency** ops-hub-A originally had — good news, not a gap. But
`stage_cidata_iso`'s destination storage (`params[:cidata_iso_storage] || connection.config[...] ||
storage`, `proxmox_provider.rb:1041-1043`) falls back to the **same** storage as the boot disk if not set
explicitly. rna's `local-data` storage.cfg entry lists `content images,rootdir` only — **no `iso`, no
`snippets`, no `import`.** If boot-disk storage is fixed to `local-data` but the cidata ISO isn't given its
own target, the ISO upload will hit a pool that doesn't declare `iso` content and should fail. PVE's own
default `local` (dir-type, `content rootdir,import,images,snippets,iso,vztmpl`, exists per-node, **not**
shared) is available on every node including rna and is the natural target — also keeps this fully
node-local (no NFS dependency at all, stronger than what ops-hub-A itself has). This needs the same
params-threading fix, extended to `options[:cidata_iso_storage]`.

### 2.3 Extended `build_provider_params` — APPLIED, don't invent a new mechanism

**Status: applied and committed 2026-07-24**, operator-approved. Addition to `build_provider_params`
(`provisioning_service.rb`, in the existing `root_volume_size`/`ssh_key` option-forwarding block):

```ruby
# Explicit placement pins. Proxmox's create_instance already reads
# top-level params[:vmid]/[:storage]/[:cidata_iso_storage] (see
# ProxmoxProvider#create_vm_instance / #create_uefi_disk_vm_instance /
# #stage_cidata_iso) but build_provider_params never threads the
# caller's options hash into them — every provision silently
# auto-selects (cluster/nextid; first *shared* storage with the right
# content type), which can never land on a node-local, non-shared pool.
# Additive only: unused by every other provider adapter (aws/gcp/azure/
# openstack/local_qemu/mock/pro_cloud), and a no-op for any existing
# caller that doesn't pass these options.
params[:vmid] = options[:vmid] if options[:vmid].present?
params[:storage] = options[:storage] if options[:storage].present?
params[:cidata_iso_storage] = options[:cidata_iso_storage] if options[:cidata_iso_storage].present?
```

A 3-line, additive, single-file change with a clear blast-radius (Proxmox adapter only, opt-in per call).
Landed as `extensions/system` commit **`9edd004ad0d9c0be95fe97e242b2e20a73ef1ae3`** (branch
`worktree-agent-af5d1ff6c46c7e2d0`, this worktree only — not pushed, not on `develop`/`master`), with the
parent superproject's submodule pointer bumped to match in the same worktree. Test coverage added to
`provisioning_service_spec.rb`: a positive spec confirming pinned `vmid`/`storage`/`cidata_iso_storage`
reach the provider adapter, an independent-pinning spec (storage alone, no vmid), and two regression specs
proving the keys stay **absent** (not merely falsy) when `options` omits them or doesn't mention them at
all — protecting the "no existing caller is affected" claim mechanically rather than by inspection alone.
Full suite: **43 examples, 0 failures** (39 pre-existing + 4 new), run against this worktree's isolated
test DB. This was the primary recommended path (over the two alternatives below) precisely because it
keeps provisioning declarative/idempotent/repeatable for the *next* member too (P1-b's witness, or a
future third member), which a one-off manual `qm` sequence would not.

**Alternative considered and rejected as primary: manual `qm create` + DB "adopt."** Import the same
published OCI disk-image artifact by hand on rna via `pvesm`/`qm`, build the VM config to mirror
ops-hub-A's shape, then hand-write a matching `System::Node`/`System::NodeInstance` row (`cloud_instance_id`
= `"rna/qemu/9100"`, `provider_region_id`, `provider_instance_type_id`, `config`, `status`) so the platform
tracks it identically thereafter. This works with zero code changes and would have been a legitimate
fallback had the operator preferred nothing touched in `provisioning_service.rb` — moot now that the §2.3
fix is applied, but recorded here in case a future member needs provisioning before some other prerequisite
fix lands. It's imperative, not idempotent, and every future member would repeat the same manual dance —
I'd only use it as a deliberate, explicitly-chosen stopgap, not the default.

**Alternative considered and rejected: a new GitOps-style declarative pipeline.** The platform already has
one (`System::Gitops::Reconciler`, `docs/gitops.md`) — but it reconciles a Node's *declared module set*
against a git-tracked `fleet.yaml` for **existing** nodes; it is not a VM-placement/creation mechanism, and
misusing it for that would blur "reconciler manages desired state" with "one-time infra action creates a
VM" — a layering mismatch. Where GitOps **is** the right tool: declaring B's NodeModule assignments (§3)
in a tracked `fleet.yaml`, if the operator wants the module *set* (not the VM's existence) under GitOps
management going forward. I'd treat that as a nice-to-have refinement, not a P1-a blocker.

## 3. What "golden image + config-in-git" concretely means here

**I initially assumed ops-hub-A ran the manual systemd-installer path
(`docs/operations/single-node-bootstrap.md` + `scripts/systemd/powernode-bootstrap.sh`)** — that doc
explicitly says it's "the path used by `dev.ipnode.us` and the `ops` control plane," and `qm config 104`'s
`cicustom:`/`ide2:...cloudinit` lines look like a plain cloud-init VM. **That assumption was wrong** — both
`create_vm_instance` (cloud_init) and `create_uefi_disk_vm_instance` (uefi_disk) build that same
PVE-native cloudinit drive shape (`build_qemu_vm_body`'s fixed `"ide2" => "#{storage}:cloudinit,..."`), so
it isn't a distinguishing signal. What **does** distinguish them: `create_uefi_disk_vm_instance` defaults
`vga` to `"serial0"` (`proxmox_provider.rb:1293`, specifically because "uefi_disk images are custom minimal
pivot-boot builds with no [VGA] recovery path"), whereas `create_vm_instance`/`build_qemu_vm_body` defaults
`vga` to `"std"`. Live `qm config 104` shows `vga: serial0` — matching `uefi_disk`, not `cloud_init`.

**Confirmed via the DB** (`rails runner`, read-only, from `/opt/powernode/server`): the "ops-hub" `System::Node`
(`019f4ebc-a4d3-...`) is bound to `NodeTemplate` **`powernode-ops-hub`** (`019f4eb9-7be7-...`,
`admin_user: pnadmin`, `config["boot_mode"] = "uefi_disk"`), whose `node_platform` is **`NodePlatform`
`ubuntu-24.04-amd64-uefi`** (`019e7c7e-0468-...`):

```
disk_image_file_object_id: 019f7a2d-4d60-7478-8960-ddef54fc59d2
disk_image_git_sha:        a60b0a0d4da8feba5271e6990929da974a836af6
disk_image_oci_ref:        git.powernode.org/powernode/disk-images/ubuntu-24.04-amd64-uefi:a60b0a0d...
disk_image_publication_status: published
disk_image_built_at:       2026-07-19 11:40:25 UTC
```

This **is** the disk-image-CI pipeline (`docs/DISK_IMAGE_CI.md`) — real, live, currently active, built 5
days before this session. **The golden image already exists; there is nothing to build.**

The software layer ("what turns a generic UEFI-boot Ubuntu image into *ops-hub*") is likewise already
git-tracked and reproducible: the `powernode-ops-hub` NodeTemplate carries an 11-`NodeModule` closure,
auto-applied to any Node bound to the template via `ProvisioningService#apply_node_template`
(→ `System::TemplateApplyService`, called unconditionally post-provision). Verified live on ops-hub's Node
(11 `NodeModuleAssignment` rows, `auto_resolved: false`, each carrying a `source_template_module_id` whose
UUIDv7 time-prefix matches the template's own — i.e. seeded from the template's declared closure, not
hand-assigned):

```
base-os-ubuntu-noble, postgres-primary, powernode-extension-system, powernode-hub-backend,
powernode-hub-frontend, powernode-hub-worker, powernode-system-base, qemu-guest-agent, redis,
reverse-proxy-traefik, runtime-ruby
```

`NodeModuleAssignment` has no version-pin column — it associates a Node with a *module*, and each module's
currently-promoted version is what the on-node agent's reconcile loop composes. So **B inherits both
"golden image" (boot disk) and "config-in-git" (module set) automatically by being bound to the SAME
`powernode-ops-hub` NodeTemplate** — no new template, no new image, no manual module list to reconstruct.
This is `docs/operations/single-node-bootstrap.md`'s manual procedure's *automated, versioned, git-tracked
successor* — I did not independently read each module's internal install script, but ops-hub-A's own live,
running state is existence-proof the template+module combination produces a working Powernode deployment;
re-deriving that from source would be redundant.

**Scope boundary, stated explicitly**: this reproducibility is real but not yet the *full* INV-2/3
guarantee (dm-verity, measured boot-counter rollback below the payload) — that machinery is what P0-b/P2/P3
are building for the fleet-substrate boot path generally, and it applies here too once landed, but nothing
about *this* increment (P1-a) needs to wait on it. B being "cattle" at the P1-a level means "rebuildable
from the same published disk image + module closure," not yet "A/B-slot rollback-protected" — that
protection, once P2/P3 land, will cover B for free since it shares the same NodePlatform/pipeline as A.

## 4. VMID and placement

**Cluster-wide VMID inventory** (`pvesh get /cluster/resources --type vm` on dna, this session): 100, 101,
103, 104, 105, 106, 107, 108, 110, 112, 114, 200, 202, 206, 210, 220, 300, 301, 500-503, 9000, 9001 — 23
VMIDs, all accounted for (rna's 7 stopped legacy VMs match the ground truth exactly: 101/103/106/110/112/
206/301). **9002 does not yet appear live** (P0-b's throwaway is apparently not yet created, or was
torn down before this snapshot) — avoided regardless, per instructions, to not race a concurrent task.

**VMID 9100 — approved by the operator (2026-07-24).** Verified free both live (absent from the 23-VMID
list above) and in the Powernode DB (`System::NodeInstance.where("config->>'cloud_instance_id' LIKE
'%/9100'")` — no match; same check run for 9101/9102/9003/302, all free; 115 is **in use** in the DB, ruled
out). Not yet consumed — no VM, `ProviderRegion`, or `Node` has been created; provisioning is still gated
on P0-b's rollback-proof gate (see the status banner at the top of this doc).

Reasoning for 9100 specifically, and the **`9100-9199` "permanent RCP member" block convention — also
approved, use going forward** (document it here as the reserved-block record of note):
- Avoid the `500-503` block — that's the `ci-native-builders-amd64` pool's *floor* (`vmid_min: 500` on the
  one Proxmox `ProviderConnection`, confirmed via DB) — churning CI builders come and go there.
- Avoid `9000-9002` — confirmed in use/reserved (`9000` = ops-hub-dev-cell, `9001` = watchdog, `9002` =
  P0-b throwaway). All three are **ephemeral/utility** VMs, semantically different from a **permanent**
  consensus member — mixing B into that block risks a future "reap the 900x scratch VMs" script treating
  B as disposable.
- **Proposal**: a new `9100-9199` block for *permanent* RCP consensus-group members. B = 9100; reserve 9101
  for P1-b's witness/QDevice VM (small, per INV-7 "third independent failure domain" — not this cluster's
  4 nodes at all, but worth reserving the number now for consistency if it ends up here).
- ops-hub-A (104) stays as-is (grandfathered, pre-RCP; not renumbered — out of scope and would touch VM
  104, which is off-limits).

**PVE node placement**: create a new `System::ProviderRegion` — **does not exist yet** (today there is
exactly **one** `ProviderRegion` for the Proxmox provider, `region_code: "dna"`; nothing for fna/lna/rna).
This alone (independent of the code gap in §2) is why a naive call defaults to dna: rna isn't even a
selectable placement target in the catalog yet.

```
provider_id:  019e446f-916c-75d2-8f4d-b44bf7cb8664   # "IPNode-PVE", the one existing Proxmox Provider
name:         "rna"
region_code:  "rna"                                   # MUST equal the PVE node name exactly — this
                                                       # string is passed directly to
                                                       # /api2/json/nodes/#{region_code}/qemu
machine_image: nil                                    # irrelevant for uefi_disk (image resolves via
kernel_image:  nil                                    # NodePlatform, not region) — matches the existing
                                                       # "dna" region's own nil/nil, for consistency
enabled:      true
```

**ProviderInstanceType**: reuse the existing **`pve.vm.large`** (`019f373f-283f-7893-b7eb-cca9e46a6ca7`) —
ops-hub-A's live spec (8 cores, 16384 MB, 160G disk) is an exact match for this preset; no new catalog
entry needed.

**Node**: a **new**, distinct `System::Node` (proposed name **`ops-hub-b`**), bound to the *existing*
`powernode-ops-hub` NodeTemplate, and no `lifecycle_class` (this text originally said
`lifecycle_class: "persistent"`, matching `PlatformDeploymentOrchestrator#resolve_or_provision_node!`;
IMP-19843220ac68 retired `system_nodes.lifecycle_class` and removed that write, so a durable non-pool
node now records no class at all). I
considered reusing the *same* "ops-hub" Node with a second NodeInstance under it, and reject that: RCP's
entire point is that A and B are independent, separately-terminable, separately-monitorable peers, not two
interchangeable instances of one logical role — a shared Node row would conflate their health/lifecycle at
exactly the layer that needs to tell them apart.

**Composed call** (illustrative — not executed):

```
System::ProvisioningService.provision_instance(
  node: <new "ops-hub-b" Node>,
  provider_region_id: <new "rna" ProviderRegion>.id,
  provider_instance_type_id: "019f373f-283f-7893-b7eb-cca9e46a6ca7",  # pve.vm.large
  operation_id: "rcp-p1a-ops-hub-b-<timestamp>",
  options: {
    vmid: 9100,                       # requires the §2.3 fix
    storage: "local-data",            # requires the §2.3 fix
    cidata_iso_storage: "local",      # requires the §2.3 fix (see §2.2 content-type nuance)
    name: "ops-hub-b"
  }
)
```

boot_mode is **not** passed explicitly — it inherits `"uefi_disk"` from the template, which is exactly what
makes the region-based node placement work (§2.1).

## 5. Safe intermediate state — B before P1-b's consensus wiring

Recommendation: provision B as **standalone** in the same sense
`System::PlatformDeploymentOrchestrator` draws the line (fresh, sovereign platform — own admin account, own
Postgres/Redis, own JWT/AR-encryption secrets, **no** `FederationPeer` row) — not the "federated" /
`managed_child` pattern (that's the Go-agent-only fleet-member shape, a different thing entirely from "a
peer Powernode control-plane deployment").

Concretely, "just another instance, not yet a quorum member" means:
- **Own identity, not A's.** B gets its own hostname/DNS name and its own ACME certificate — explicitly
  **not** `ops.ipnode.us` (or whatever ops-hub-A's live hostname is) and not sharing its cert. Claiming A's
  identity is P3's job ("Floating control-plane role via SDWAN VIP... distinct from the stable per-node
  LAN identity"), not this increment's. **Flagged for operator**: what B's own hostname should actually be
  (e.g. `ops-hub-b.ipnode.us`) — I don't have a naming convention to draw on beyond the `fleet-dns-*`
  pattern, and didn't want to assume.
- **Own data, not A's.** B's Postgres seeds fresh (`SEED_ADMIN_USERS`-style first-boot admin, per
  `single-node-bootstrap.md`'s gotcha #4 — whatever the `powernode-hub-backend` module's own init
  script does at first boot). The campaign's own phrase for P1 is "golden image + config-in-git **+ PBS**"
  — i.e. state continuity across members is a **backup/restore** model (Proxmox Backup Server), not live
  replication; wiring that up is later-phase work, not P1-a's. B starting with empty/fresh state is the
  correct, conservative starting point.
- **Not in the traffic path.** No DNS/VIP pointing at B yet; it's reachable directly (by IP or its own
  hostname) for health-check/monitoring purposes only.
- **Recommend**, don't require: a `System::PlatformDeployment` bookkeeping row (so B shows up in the
  Scaling panel) — `PlatformDeploymentOrchestrator#deploy_standalone!` would normally create this, but it
  hardcodes its own `options:` hash and doesn't forward a caller-supplied one (checked — `params[:options]`
  is never read in `deploy_standalone!`), so using it as-is would silently lose the `vmid`/`storage` pins
  from §4. Either extend the orchestrator to forward `params[:options]` too (small, same-shape fix as §2.3),
  or call `ProvisioningService` directly (§4) and create the `PlatformDeployment` row as a separate,
  explicit step.

## 6. Verifying the acceptance criteria

| Criterion | How to verify | Notes |
|---|---|---|
| B healthy | `systemctl status powernode-{backend,worker,worker-web,frontend,reverse-proxy}@default --no-pager` over SSH, all `active` | Do **not** trust `System::NodeInstance.status` alone — see finding below |
| `/up` 200 | `curl -sI http://<B's address>:3000/api/v1/health` (or whatever `/up`-equivalent route the backend exposes) from **outside** B, not just `curl localhost` on the box itself | Match P0-a's probe vantage point (external, not self-reported) — see coordination note below |
| On rna's independent zpool | `qm config 9100` on rna (or cluster-wide via `pvesh`): confirm `scsi0`/`efidisk0` volids are prefixed `local-data:...`, and that this `local-data` is rna's own (already ground-truthed as physically independent from dna's) | Exactly the check I ran against 104 this session — same recipe, different VM |
| Reproducible from golden image | Compare B's `booted_image_git_sha` (once the agent reports it, `System::NodeInstance.booted_image_git_sha`) against the `ubuntu-24.04-amd64-uefi` NodePlatform's `disk_image_git_sha` (`a60b0a0d4d...`) — should match exactly. Optionally, as a repeatability drill: re-run the same call against a throwaway VMID and diff the resulting `qm config` against B's, modulo vmid/mac/uuid | Could fold into P1-c's scrutiny (first-peer-delivery gate) rather than duplicating effort here |

**Coordination point — resolved**: I asked `rcp-p0a-monitoring` (the P0-a external-probe/alerting increment)
how its target is configured, to point this doc at a concrete integration seam instead of recommending a
second, redundant health-check mechanism. Answer: the watchdog is deliberately DB/API-free (must keep
working even if the whole platform is unreachable) — a plain shell `EnvironmentFile` at
`/etc/powernode/ops-hub-watchdog.conf` (`TARGET_NAME`/`TARGET_URL`/`TARGET_PING_HOST`), sourced by its
systemd unit. **Adding B as a second monitored target is: a second config file
(`/etc/powernode/ops-hub-b-watchdog.conf`, `TARGET_NAME=ops-hub-b`, `TARGET_URL=<B's /up>`) + a copy of the
shipped systemd unit repointed at it** (`ExecStart`/`EnvironmentFile`/`SyslogIdentifier`) — same script,
independent unit/timer pair. Full recipe now documented in `docs/operations/ops-hub-watchdog.md` under
"Monitoring multiple targets (e.g. ops-hub-B)". While confirming this, they found and fixed a real bug:
the on-disk *state* file was already correctly keyed by `TARGET_NAME`, but the Prometheus
textfile-collector *metric* file used a static filename — two instances would have clobbered each other's
gauge output (logging/alerting stayed correct; only the Prometheus metric was wrong). Fixed, verified two
independent instances produce independent correct files, redeployed to the live VM. **Recommendation for
P1-a: reuse this pattern verbatim (second config + second unit) rather than building anything new** — a
unified "all ops-hub instances" view across N targets is a small further step they flagged as not yet
built (only one target exists today); not needed for this increment's acceptance criteria (a single B
health check), worth revisiting once a third member (the P1-b witness, or beyond) makes N > 2.

**Discovered, not fixed, flagged for operator**: ops-hub-A's own live `System::NodeInstance` row
(`019f680e-d4ff-...`, `cloud_instance_id: dna/qemu/104`) currently shows **`status: "error"`** in the
Powernode DB, despite the VM being demonstrably healthy and running live (uptime ~13h at time of check,
per `pvesh`). This is a pre-existing drift between the platform's cached status and reality, unrelated to
P1-a — but it directly informs the "B healthy" verification above: **don't rely solely on
`System::NodeInstance.status`** as a health signal for either A or B, it's already proven unreliable for A.
Recommend queuing this as its own small fix (likely a missed `sync_status`/heartbeat reconciliation after
the dna-data→local-data migration) — separate from this campaign.

Also worth a small side note while investigating VMID history: the DB carries several older, `error`/
`terminated` `NodeInstance` rows for "ops-hub" at vmid 102 (2026-07-11/12, several attempts) before 104
succeeded on 07-15 — consistent with "ops-hub was hand-evolved, not cattle" per the task brief; not
something to clean up as part of P1-a, just noting the history matches expectations.

## 7. Explicit non-goals for this increment

- Does **not** join any consensus/quorum construct — that's P1-b (corosync+QDevice, `wait_for_all`,
  asymmetric fencing delay).
- Does **not** wire a floating control-plane VIP or claim A's identity — that's P3.
- Does **not** implement verify-before-pivot / TUF-Uptane / attestation-before-relay — that's P2.
- Does **not** touch VMIDs 9001, 9002, or VMs 104 (ops-hub-A) / 105 (opn-1).
- **Does not yet create the `ProviderRegion`, the `Node`, or the VM itself.** The §2.3 code fix is applied
  (prerequisite, code-only, no live infrastructure), and VMID 9100 + the block convention are approved —
  but actual provisioning is gated on **P0-b's boot-counter rollback-proof gate closing** and stays paper
  until that gate closes and an operator/orchestrator explicitly greenlights execution.

## 8. Open questions for the operator

**Resolved 2026-07-24**: Q1 (code fix vs. manual-adopt) → code fix approved and applied. Q2 (VMID
convention) → approved, 9100 reserved for B, `9100-9199` reserved for permanent RCP members going forward.

Still open:

1. Approve Node name `ops-hub-b` and region name/code `rna`?
2. What hostname/DNS name should B itself answer to (explicitly *not* A's)?
3. Should a `System::PlatformDeployment` bookkeeping row be created for B (Scaling-panel visibility), and
   if so, via an orchestrator fix or as a separate manual step?
4. Should the ops-hub-A `NodeInstance.status` staleness (§6) be queued as its own fix now, or bundled into
   a later RCP phase's monitoring work? (Already filed as platform observation `019f93e8-644a-7d43-9932-
   7d5fe225ffbb` — this question is about priority/ownership, not whether to track it.)
5. When P0-b's gate closes, who executes the actual provisioning — this same increment resumed, or a
   fresh execution pass referencing this design doc?

---

_Prepared as a paper design for RCP P1-a. All Proxmox/DB reads in this document were run read-only
(`pvesh get`/`qm config` via SSH to dna; `rails runner` read-only queries from `/opt/powernode/server`) —
no Proxmox VM and no live DB row was ever created or modified. The one exception, done under explicit
operator approval after the initial design pass: the §2.3 `provisioning_service.rb` fix + its spec,
applied and committed inside the `extensions/system` submodule in this worktree only (not pushed, not on
`develop`/`master`) — see the status banner at the top of this document._

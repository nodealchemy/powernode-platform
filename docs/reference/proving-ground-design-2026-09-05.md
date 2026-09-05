# Proving Ground — Design (2026-09-05)

**Ask (operator):** "a well rounded environment consisting of all necessary instances and SDWAN
fabric to prove all aspects of our management capabilities."
**Layout:** §1 and §5–§9 are the SDWAN half (the fabric that every other family rides on, and
the diagnosis of why it has never carried a packet). §2–§4 and §12–§15 are the wider proving
ground: capacity, blast-radius boundary, the capability matrix, the per-family four-question
analysis, the environment roster and the increments. The SDWAN half was accepted as campaign
proposal `01a07051-8d33-78c9-9fc2-f42ef4d92c3e` and is not re-argued here.
**Status:** design only. No code written, no live state changed.
**Method:** every claim was checked today against `extensions/system` (HEAD `3927ed0b`), the
production MCP connector, read-only shell on the Proxmox host `dna`, and two read-only
`qm guest exec` probes (payloads under 120 bytes) against the testbed VMs. Citations are
`file:line` inside `extensions/system` unless prefixed otherwise. Numbers the brief supplied
were re-measured; where they differ, §11 says so.

---

## 0. Verdict

1. **Nothing in the SDWAN plane has ever carried a packet because the promoted boot image
   cannot create a WireGuard, VRF or dummy netdev.** Image `1233cb9e` (published 2026-08-17,
   still the newest amd64 publication) predates the initramfs fix `fe5c8da4` (2026-08-20).
   VM 9005's current-boot journal shows `apply_vrfs … Unknown device type` and
   `apply_interface:wg-sdwan-1 … Unknown device type` every tick. This is fleet-wide, not a
   testbed accident; the Docker dry-run of 2026-08-09 died of the same cause (§1.4).
2. The platform could not see it because every node runs the pre-`28460bbb` agent
   (`powernode-system-base` v19, built 2026-08-17). Both are **rollouts, not code**, and
   both are operator decisions with fleet-wide reach.
3. **RAM on `dna` is the binding constraint and the current instance-type catalog has no VM
   preset under 4 GB.** A `pve.vm.tiny` (2 vCPU / 2 GB / 20 GB) must be added; with it the
   whole proving ground fits in ~28 GB, against ~104 GB available today.
4. **The self-management fence that keeps autonomy off ops-hub is inert until SiteSetting
   `self_hosting_node_id` is set, and the boot-image rollout executor does not consult it at
   all.** ops-hub is itself drifted against the promoted image, so a fleet-wide drift
   rollout would reboot the control plane. Setting the fence is increment 0.
5. The coverage matrix (§4) has 72 rows: 46 provable in dev, 16 only with an operator
   decision, 10 not provable here. The wider ground is **13 new instances, 32 GB**, plus the
   existing 16 GB builder pool (§13).
6. **Three capabilities cannot be proven safely as things stand**: ingress and certificates
   (every writer edits ops-hub's live Traefik; no node-side target exists), disk-image
   promotion and boot-image rollout (one `NodePlatform` default shared with ops-hub and a
   rollout executor with no fence, until `pg-amd64-uefi` and the fence land), and volume
   snapshot/restore (the Proxmox adapter declares no snapshot support and `dna`'s zvol
   snapshots hang).

---

## 1. Why has no handshake ever happened? (SDWAN diagnosis)

### 1.1 The path, link by link

| Link | Mechanism | Verified state for `dryrun-fabric` |
|---|---|---|
| Compile | `Sdwan::TopologyCompiler.compile_for_peer` (`server/app/services/sdwan/topology_compiler.rb:72`) | Correct and continuous. `sdwan_get_topology` returns two complete views: interface `wg-sdwan-1`, VRF `sdwan-1`, hub endpoint `10.125.0.201:51820`, spoke keepalive 25, MC envelopes rev 730 re-minted hourly. |
| Distribute | `GET /node_api/config/sdwan` → `show_config` (`server/app/controllers/api/v1/system/node_api/sdwan_controller.rb:52-109`), pulled by `Manager.fetchDesiredConfig` (`agent/internal/sdwan/manager.go:752`) from the heartbeat `PostSend` (`agent/internal/runtime/service.go:305-308`) | **Received.** The apply-health sensor reports `no_subsystem_observation`, reachable only when `sdwan_state.networks` is non-empty (`sdwan_apply_health_sensor.rb:252-256`), which requires a successful fetch (`manager.go:561-575`). |
| Apply | `apply_vrfs` (`manager.go:155`; `vrf_applier.go:189`) then `apply_interface` (`manager.go:279`; `wg_applier.go:89`) | **Never applied.** Journal on VM 9005 this boot: `apply_vrfs: create vrf sdwan-1: ip link add: exit status 2; Error: Unknown device type.` then `apply_interface:wg-sdwan-1: … Unknown device type.` `ip -br link` on both VMs shows only `lo` and `enp6s18`; `wg show` prints nothing; no `wireguard` module loaded. From `dna`, UDP 51820 on 10.125.0.201 answers port-unreachable (team-lead's probe). |
| Observe (tunnel) | `wg show … dump` → `POST /status/sdwan` (`manager.go:492`; controller `:139-169`) → `Peer#recompute_status_from_handshake!` (`server/app/models/sdwan/peer.rb:333-347`) | Never reached; peers `pending`, `last_handshake_at` null, counters null. |
| Observe (apply) | heartbeat `sdwan_state` → `Sdwan::AgentApplyStateWriter` (`node_api/status_controller.rb:154-160`) → `SdwanApplyHealthSensor` | Block arrives without `subsystem_states` (pre-`28460bbb` agent); the sensor can only say "unknown". |

### 1.2 Why the kernel refuses, and why no reboot fixes it

- The pivot rootfs has no `/lib/modules`; netdev types that are `=m` on Ubuntu 24.04 must be
  force-included in the initramfs and loaded pre-pivot. The incident is written up in
  `initramfs/modules.d/90powernode/powernode-sdwan.conf:9-21`; the fix adds the modules to
  `build.sh`'s `--force-drivers` (`initramfs/build.sh:332,352`), a `modules-load.d` entry
  (`module-setup.sh:268-276`) and a belt in `powernode-mount.service:59`.
- `fe5c8da4` is on `origin/develop`; `git log 1233cb9e..origin/develop -- initramfs/` lists
  exactly that one commit as unshipped. `powernode-sdwan.conf` does not exist in tree
  `1233cb9e`. **Every node in the fleet boots an image without it**: testbed on `1233cb9e`,
  dev-cell on `6924d16c`, ops-hub on `ff844e0f` (team-lead's DB read). Rebooting onto the
  promoted image changes nothing; **an image must be built and promoted first**.
- Corollary: boot-image drift is measured as booted-vs-promoted, never promoted-vs-code, so a
  promoted image 19 days behind develop and missing a capability the code depends on is
  invisible to every sensor. The proving ground needs a "is the promoted image capable of
  what the code assumes" oracle, not only "does this node match the promoted image" (§7).

### 1.3 Why the platform cannot see it

- `28460bbb` (per-subsystem apply outcomes on the wire) landed 2026-08-20 20:04 UTC. The
  agent reaches nodes through the `powernode-system-base` overlay; v19 (digest
  `2b4dae81…`, current on all 99 assignments) was built 2026-08-17 19:06 UTC (UUIDv7 of
  version id `01a0111e-96d3`). `git log --since=2026-08-17T19:06 origin/develop -- agent/`
  lists **43 unshipped agent commits**, including the verify-probe runner (`b4f41c35`), the
  real agent-version stamp (`efcc24fa`; both nodes still report `agent_version: "dev"`),
  memory/CPU/GPU heartbeat fields, the taskguard seam and the OVN activation lane.

### 1.4 Three-way distinction, and the collapsed rows

| Hypothesis | Verdict |
|---|---|
| Agent never received config | No — `sdwan_state.networks` non-empty; journal names `wg-sdwan-1` |
| Received, never applied | **Yes** — `Unknown device type`, every tick, this boot |
| Applied, observation missing | No, but a second blindness sits on top: the running agent cannot report per-subsystem outcomes |

Rows in the coverage matrix that collapse into this one prerequisite: the six
`Devops::DockerHost` rows from the 2026-08-09 dry-run are all `pending` with API endpoints on
`fd45:a2b6:00d8:155b::/64` — Docker binds to the overlay `/128` (`docker_provision`
executor description) and the overlay never existed; K3s over SDWAN, VIP-backed services,
DB VIP for `promote_replica`, `service_discovery_composer`, and every SDWAN row.

### 1.5 Latent defects found on the trace

1. **Firewall/NAT chains are keyed on a different interface name than the WireGuard
   interface.** Interface: `wg-sdwan-<HostVrfAssignment.short_id>` (`host_vrf_assignment.rb:80-82`, `topology_compiler.rb:389`) = `wg-sdwan-1`. `FirewallCompiler#interface_name`: `wg-sdwan-<network_handle>` (`firewall_compiler.rb:84-97`) = `wg-sdwan-019fe6`. Every `iif` clause (`:111-118`) matches nothing; the manager's orphan teardown derives chain suffixes from the real name. Same split in `NatCompiler` (`nat_compiler.rb:51,80,89`).
2. **Hub auto-enrollment cannot elect a hub on Proxmox.** `auto_enroll_sdwan_peer!` (`provisioning_service.rb:816-850`) needs `private_ip_address` at provision time; on Proxmox it is learned later via the guest agent (`proxmox_provider.rb:1858`) and both testbed rows still have `private_ip: null` despite the worker's `system_cloud_sync` job (`worker/config/sidekiq_system.yml:129-131`). The fallback, "hub promotion left to the failover sensor", is planning-only (`sdwan_failover_executor.rb:1-17`).
3. **The testbed SKU is 16 GB / 160 GB** (`pve.vm.large`) and auto-classifies heavyweight (`HEAVYWEIGHT_MIN_MEMORY_MB = 4096`, `node_instance.rb:81,770-787`), so any host bridge would compile as `ovs`-kind and fail (no `ovs-vsctl`, `ovn_controller_applier.go:240-249`).
4. **`parse_time` fabricates a fresh handshake on a malformed timestamp** (`sdwan_controller.rb:313-317`).
5. **Reachability/drift/VIP windows are constants** (`sdwan_reachability_sensor.rb:22`, `sdwan_drift_sensor.rb:17-18`, `sdwan_vip_reachability_sensor.rb:23`); only apply-health reads `SiteSetting` (`:193-194,434-439`). `get_sensor_config` lists four sensors, none SDWAN.

---

## 2. Capacity on `dna`, and the RAM budget

### 2.1 Measured 2026-09-05 06:4x UTC (read-only, from `dna`)

| Metric | Value | Note |
|---|---|---|
| RAM | 251 GB total, 147 used, **104 available**, 16 cores | matches the brief |
| Configured RAM of *running* VMs | 228 GB | 12 running guests; overcommitted, so "available" is the real ceiling |
| Running guests | vault 4 G, acs 16 G, **dev (300) 64 G**, ops-hub 16 G, dev-cell 16 G, ops-cell 16 G, sdwan-test-a/b 16 G each, **four ci-native-builders 16 G each (9002, 9004, 9008, 9010)** | the pool reports `ready 1`, so three running builders (48 GB) appear orphaned — verify before reclaiming |
| Stopped guests | ops-old, windi, windo, gns, gns-1, builders 9006 and 9009 | **stopped KVM guests hold no RAM**; they hold thin disk only |
| ZFS pool | 14.5 T, 13.1 T alloc, 1.48 T free raw; `local-zfs` **606 GB AVAIL** logical | `dna-vault` 5.84 T, `local-data` 360 G; 295 snapshots |
| Instance-type presets | `pve.vm.small` 2 vCPU / **4096 MB** / 20 GB; medium 4/8192/80; large 8/16384/160; lxc tiers 2/4/8 GB (`proxmox_provider.rb:79-84`) | **no VM preset under 4 GB, and 4096 MB is exactly the heavyweight threshold** |

### 2.2 Finding: add `pve.vm.tiny`

Add `{ code: "pve.vm.tiny", vcpus: 2, memory_mb: 2_048, storage_gb: 20, mode: "vm" }` to
`INSTANCE_TYPE_PRESETS` and let catalog sync materialize the row. Every WireGuard/BGP/spoke,
user-device, Docker and K3s-agent role runs in 2 GB. Pass `network_profile: "lightweight"`
explicitly on every provision regardless of size (`system_fleet_tool.rb:1241`) so the
4096 MB auto-classification never decides for us.

### 2.3 RAM budget (phase 1–2 proving ground)

| Role | Count | GB each | Total | Type |
|---|---|---|---|---|
| SDWAN hubs (hub-a, hub-b) | 2 | 2 | 4 | tiny |
| Gateway + NFS export host (gw-1, `storage-tools`) | 1 | 2 | 2 | tiny |
| Postgres primary + replica (db-1, db-2; `postgres-primary`/`-replica` modules) | 2 | 4 | 8 | small, explicit lightweight |
| K3s server (`get.k3s.io` install at runtime, needs egress) | 1 | 4 | 4 | small |
| K3s agent | 1 | 2 | 2 | tiny |
| Docker host (`dev-cell-docker` module, overlay-bound daemon) | 1 | 2 | 2 | tiny |
| User-device role (ud-1) | 1 | 2 | 2 | tiny |
| Ephemeral spoke pool (DR warm spare + churn), `max_size 2` | 2 | 2 | 4 | tiny |
| **Phase 1–2 total** | **11** | | **28 GB** | 11 × 20 GB thin disk = 220 GB |
| Existing CI builder pool (`target_size 1`) | 1 | 16 | 16 | unchanged |
| Phase 3 heavyweight OVS/OVN chassis | 1 | 8 | 8 | medium |
| Phase 3 `ovn-central` | 1 | 4 | 4 | small |
| Phase 3 second control plane (platform federation, `powernode-hub` template) | 1 | 16 | 16 | large — operator decision |

Phase 1–2 fits in 28 GB of the 104 GB available with no reclaim. Reclaim levers, priced,
each an operator decision: the three apparently orphaned running builders (48 GB, verify via
pool membership first); VM 300 `dev` (64 GB; blocked by the standing "no decommission before
the replacement VM exists" rule); stopped guests (disk only, ~1 TB of thin zvols).

---

## 3. Blast-radius boundary: ops-hub is never a test subject

What enforces it today, and what does not:

- **`System::Autonomy::SelfManagementFence`** (`server/app/services/system/autonomy/self_management_fence.rb`) refuses reap/actuate on the node named by SiteSetting `self_hosting_node_id`. It is **nil-safe and inert by default** (`:52-58`). It gates `reboot_silent_instance`, `converge_instance_state_drift`, `quarantine_honeypot_instance`, `apply_template_closure_drift` and `dispatch_reconcile_task` in the DecisionEngine (`decision_engine.rb:2136,2188,2267,2780,2835`), plus `platform_resilience_executor.rb` and `executors/terminate_instance.rb`. **I could not read the SiteSetting; assume unset until verified.**
- **`ControlPlaneFence`** (`control_plane_fence.rb:56`) is stamp-based and explicitly dormant until the cutover runbook stamps instances.
- **`boot_image_drift_rollout_executor.rb` consults neither fence** and its declared blast radius is "reboots every drifted node on the platform" (`:56`). ops-hub (booted `ff844e0f`) is drifted against the promoted `1233cb9e`, and after increment 1 promotes a new image *every* node is drifted. An approved fleet-wide rollout would reboot ops-hub.
- `Sdwan::ServiceExposureWriter` and `Acme::TraefikConfigWriter` write ops-hub's live Traefik dynamic dir (`service_exposure_writer.rb:7-11,90`).

Design rules, in force for every increment:

1. **Set `self_hosting_node_id` to ops-hub's Node id before anything else** (increment 0) and add the fence check to `boot_image_drift_rollout_executor` and `disk_image_promote`'s rollout path.
2. Proving-ground nodes carry the name prefix `pg-` and live on dedicated templates
   (`pg-*-amd64`) and a dedicated pool; the harness refuses any instance whose node is not on
   a `pg-*` template. ops-hub, dev-cell and ops-cell hold no `Sdwan::Peer`, no `pg-*`
   template and are never passed to an executor by the harness.
3. Boot-image rollouts target an explicit `pg-*` instance set, never the platform-wide batch.
4. Service-exposure and ACME rows are exercised **only** by an operator-run pass, because they
   touch ops-hub's Traefik.
5. Intervention policies for `pg-*` scoped actions may be `auto_approve`; the same categories
   fleet-wide stay `require_approval`. The autonomy-gate row in §4 proves that the gate blocks.

---

## 4. Capability coverage matrix

Derived from `docs/SKILL_EXECUTOR_CATALOG.md` (65 executors: Devops 39, Documentation 1,
Federation 5, Fleet 10, Governance 1, Sdwan 5, Security 3, System 1), the 36 sensors in
`System::Fleet::FleetAutonomyService::SENSORS`, the 34 `smoke_test_*.rb` seeds in nine passes
(`docs/SMOKE_TEST.md` says 28), and the MCP catalog (`docs/reference/auto/mcp-tools.md`,
625 headings). Live counts today: `Sdwan::Service` 0, volumes 0, GitOps repos 0, federation
peers 0, package repositories 1 (Ubuntu Noble, `syncing`, 0 packages, never synced), managed
Docker hosts 6 (all `pending`, all orphans of the 08-09 dry-run), node rows 100 (nearly all
`ci-native-builders-*` leftovers).

Status key: **DEV** provable in the proving ground · **OP** provable only with an operator
decision · **NO** not provable here (and why). "Oracle" is always a positive observation.

### A. Boot, enrol, compose

| # | Capability (executor / sensor / tool) | Needs | Positive oracle | Status |
|---|---|---|---|---|
| A1 | Provision on Proxmox, UEFI-disk boot, enrol, pivot (`provision_instance`, `smoke_test_pivot_root`) | 1 tiny node | heartbeat with `booted_image_git_sha` = promoted sha, `lkg_present`, `running_module_digests` = assigned set | DEV |
| A2 | Module attach / hot refresh / drift (`refresh_instance_modules`, `ModuleDriftSensor`, `drift_remediate`) | 1 node | digest appears in `running_module_digests`; `module_drift` empty; on a deliberately unassigned module the sensor emits and the plan lists it | DEV |
| A3 | `verify:` probes (`ModuleVerifyFailedSensor`) | 1 node on a post-`b4f41c35` agent | `module_verify_state` present with a passing probe; a manifest with a wrong `resolves_to` yields a `failed` report | DEV (after inc. 2) |
| A4 | Module build → publish → promote → rollback (`dispatch_module_build_batch`, `promote_module_version`, `rollback_module_version`, `module_smoke_verify`, `ModulePromotionSensor`) | builder pool + 1 node | new version digest appears on the node; rollback digest reappears; `module_smoke_verify` unit-active check on a pooled instance | OP (publish auto-promotes fleet-wide; use a `pg-only` module) |
| A5 | Disk image build → publish → promote → rollback → retention (`disk_image_*`, `BootImageDriftSensor`, `DiskImagePublicationFailureStreakSensor`, `smoke_test_disk_image_build_to_publication`) | Gitea CI runner + 1 `pg-*` node | publication row with sha256 matching the artifact; a `pg-*` node reboots and reports the new sha; rollback reverts the default; retention purges exactly N | OP (promotion affects every future boot incl. ops-hub) |
| A6 | Boot-image drift rollout (`boot_image_drift_rollout`) | ≥2 drifted `pg-*` nodes | canary reboots first, reports new sha, batch 2 follows; a failed canary halts (`halted: true`) | OP (must be scoped to `pg-*`; fence gap §3) |
| A7 | Boot LKG arming (`BootLkgArmSensor`, `booted_from_lkg`) | 1 node | `lkg_present: true`; with the control plane unreachable at boot (block node_api via nft on the node) the node boots and reports `booted_from_lkg: true` | DEV |
| A8 | Silent instance / unrecoverable (`InstanceStatusSensor`, `InstanceUnrecoverableSensor`, `reboot_silent_instance`) | 1 pooled spoke | stop the VM's agent; sensor emits within `silent_threshold_seconds`; reboot action lands and heartbeat resumes | DEV |
| A9 | Template closure / instance-state drift (`TemplateClosureDriftSensor`, `InstanceStateDriftSensor`) | 1 node | remove a module from the template; sensor emits; converge action reattaches | DEV |
| A10 | Bare-metal claim (`smoke_test_bare_metal_claim`) | physical device | — | NO: DB-level only; the claim flow needs a real device and `POWERNODE_CA_PEM_URL` is unset |
| A11 | arm64 / RPi images | arm64 hardware | — | NO: no arm64 host on `dna` |

### B. SDWAN fabric

| # | Capability | Needs | Positive oracle | Status |
|---|---|---|---|---|
| B1 | Handshake | hub-a + spoke | `last_handshake_at` within 3 min on both peers **and** on-node `wg show … latest-handshakes` agrees | DEV (after inc. 1) |
| B2 | Apply health (`SdwanApplyHealthSensor`) | same | every subsystem `ok`, `subsystems_reported: true`, `healthy_peers ≥ 1` | DEV (after inc. 1) |
| B3 | End-to-end packet | same | receiver `rx_bytes` delta ≥ N×1028 after `ping -c N -s 1000 -I wg-sdwan-1`; probe exit 0 | DEV |
| B4 | Firewall rule | same | `nft -j list chain` shows the rule with a non-zero counter; a `drop` rule fails the ping | DEV (after inc. 3) |
| B5 | VRF + multi-VRF isolation | hub-a in nets A+B, spoke-1 (A), gw-1 (A+B) | `ip -j vrf show`; A-only spoke cannot reach gw-1's B address (probe exit ≠ 0) while A reaches | DEV |
| B6 | iBGP + route policy + subnet advertisement + FIB (`compile_route_policy`, `SdwanBgpSessionHealthSensor`, `sdwan_bgp_session_remediate`) | hub-a RR, hub-b, gw-1 with `lan_subnets`, spoke-1 | `BgpSession` established with `prefixes_received ≥ 1`; `ip -j route show vrf sdwan-1` on spoke-1 carries gw-1's prefix; a deny policy removes it | DEV |
| B7 | VIP failover (`sdwan_vip_failover`, `SdwanVipReachabilitySensor`) | two holders + client | VIP on `d-sdwan-1` moves from holder 1 to 2; ping still answered by the new holder | DEV |
| B8 | Hub failover (`sdwan_failover` is planning-only; promotion is `update_peer publicly_reachable`) | hub-a, hub-b, spoke | after removing hub-a's peer, spoke's next handshake endpoint is hub-b | DEV |
| B9 | Port mapping / DNAT / `expose_service_publicly` VIP+DNAT half | hub + backend + dev-cell as LAN client | `curl` from dev-cell to hub LAN IP:port returns backend marker; NAT chain counter increments | DEV (Traefik half is E-row) |
| B10 | User device (`issue_user_device`, `SdwanUserDeviceConfigStalenessSensor`) | ud-1 | `UserDevice.last_seen_at` set; hub's `wg show` lists the device pubkey with a handshake | DEV |
| B11 | Key rotation / MC refresh / expiry (`sdwan_peer_remediate`, `sdwan_credential_refresh`, `SdwanCredentialExpirySensor`, `smoke_test_membership_credentials`) | live tunnel | new `PeerKey` **and** a post-rotation handshake; MC `revision` increments, `mc_validate` stays `ok` | DEV |
| B12 | Sensor truthfulness (`SdwanReachabilitySensor`, `SdwanDriftSensor`) | live tunnel | fingerprints stop emitting for two windows when up; `hub_unreachable` starts within one window when hub-a's peer is removed | DEV |
| B13 | Host bridge, linux-kind (`sdwan_host_bridge_compose`) | 1 lightweight node | bridge present in `ip -j link` with the allocated CIDR | DEV |
| B14 | Host bridge ovs-kind + IPFIX (`sdwan_ipfix_collector_compose`, `SdwanServiceHealthSensor` flow correlation) | heavyweight node with OVS + built `sdwan-flow-exporter` + collector | `Sdwan::FlowSample` row matching a probe-generated 5-tuple | OP (two modules must be built; publish auto-promotes) |
| B15 | OVN (`sdwan_ovn_compose_topology`, `sdwan_ovn_apply_acl`, `SdwanOvnDeploymentHealthSensor`) | `ovn-central` node + OVS chassis | `NbProbe :confirmed`; agent `sdwan_ovn_state` reports the replayed switch count; ACL blocks a flow | OP (§9) |
| B16 | Multi-tenant isolation (`multi_tenant_isolation`) | second network + VRF (= B5 with an iBGP RIB) | tenant B's prefix absent from tenant A's RIB and FIB | DEV |

### C. Container runtimes

| # | Capability | Needs | Positive oracle | Status |
|---|---|---|---|---|
| C1 | Docker host provision + mTLS handshake (`docker_provision`, `smoke_test_docker_runtime`, `docker_*` MCP) | docker node on the overlay | `DockerHost.status` leaves `pending`; `docker_list_containers` returns a container started via the platform | DEV (after inc. 1; the six 08-09 rows are orphans to delete) |
| C2 | K3s server bootstrap + VIP + flannel over SDWAN (`provision_cluster`, `smoke_test_k3s_site_bootstrap`, `smoke_test_flannel_over_sdwan`) | k3s-server node, egress to `get.k3s.io` | `kubernetes_list_nodes` shows Ready; pod CIDR advertised as `SubnetAdvertisement`; tcpdump on `wg-sdwan-*` carries pod traffic (`smoke_test_k3s_pod_plane` site+) | DEV if the node has internet egress — unverified |
| C3 | K3s agent join, multi-cluster `target_cluster_id` (`smoke_test_k3s_agent_join`) | + k3s-agent node | second node Ready in the cluster; a mismatched CNI join is refused | DEV (the doc marks the operator path NOT IMPLEMENTED — the row proves the platform half) |
| C4 | HA control plane | 3 servers | — | NO: `smoke_test_k3s_ha_control_plane` states an HA control plane is not implemented |
| C5 | Rolling module upgrade (`rolling_module_upgrade`) | k3s template with ≥2 instances | plan is one atomic set; after dispatch both nodes report the new digest | OP (fleet-atomic; `pg-*` template only) |
| C6 | Drain → terminate → reprovision → re-join (`smoke_test_k3s_drain_reprovision`) | pooled k3s-agent | `node_count` restored with a new instance id | DEV |
| C7 | OVN-Kubernetes CNI (`smoke_test_ovn_k8s_cni`) | B15 | pods on two nodes on one OVN logical switch | OP |

### D. Storage

| # | Capability | Needs | Positive oracle | Status |
|---|---|---|---|---|
| D1 | Volume create/attach/mount (`attach_storage`, `create_volume`, `attach_volume`) | 1 node | `findmnt` on the node at the requested path; a written marker file survives detach/attach on another node | DEV |
| D2 | Volume snapshot / restore (`snapshot_volume`, `restore_volume`, `SnapshotPolicySensor`) | provider snapshot support | — | **NO on `dna`**: zvol snapshots hang (`z_zvol` taskq wedged). Provable only after a host reboot of `dna` or on another hypervisor — operator decision |
| D3 | NFS export + storage assignment (`test_nfs_export`, `storage_assignment_*`, `StorageAssignmentDriftSensor`) | gw-1 with `storage-tools` + a consumer node over the overlay | consumer mounts the export over `wg-sdwan-1`; marker file round-trips; drift sensor emits when the assignment is deleted on-node | DEV (after inc. 1) |
| D4 | Storage migration + revert + chown (`migrate_storage_component`, `storage_chown_*`, `smoke_test_storage_migration_revert_cleanup`) | two storage targets | data present at the new target with the assigned owner; revert restores the binding | DEV (block-level copy; no snapshot needed) |
| D5 | Storage recommendations (`get_storage_recommendations`) | any | recommendation row cites a real assignment | DEV |

### E. Ingress and service delivery

| # | Capability | Needs | Positive oracle | Status |
|---|---|---|---|---|
| E1 | `Sdwan::Service` + local exposure (`expose_service_local`, `ServiceExposureWriter`) | backend on a VIP; Traefik on ops-hub | `curl https://<ops-hub>/svc/<slug>` returns the backend marker through ForwardAuth | OP (writes ops-hub's live Traefik dir; operator-run pass) |
| E2 | Public TLS exposure (`expose_service_publicly`, `expose_service_public_tcp`) | E1 + a public listener + DNS | external client reaches the service by SNI | OP (public DNS/listener on ops-hub) |
| E3 | ACME issuance/renew/revoke (`acme_*`, `CertExpirySensor`, `CertificateExpirySensor`, `smoke_test_acme_issuance`) | DNS provider credential + a test zone | LE-staging certificate row with matching SAN; renewal produces a new serial | OP (real DNS credential; staging CA only) |
| E4 | Reverse proxy compose (`reverse_proxy_compose`) | E3 | Traefik dynamic file names the cert and route | OP |
| E5 | Service discovery over the overlay (`service_discovery_composer`) | VIP + iBGP (B6/B7) | the VIP route appears in every peer's FIB; `curl` from a spoke to the VIP succeeds | DEV |

### F. Disaster recovery (APO campaign; none exercised live)

| # | Capability | Needs | Positive oracle | Status |
|---|---|---|---|---|
| F1 | `replace_instance` (warm-pool replacement, volume reattach, SDWAN re-enrol, VIP move) | pooled spoke + a victim spoke with a volume and VIP | after stopping the victim: replacement holds the volume (marker file readable), holds a peer on the same network with a handshake, and holds the VIP (`d-sdwan-*`); the victim is **not** terminated (`reap: false`) | DEV |
| F2 | `reap_instance` (separately gated destroy) | F1 | victim VM gone from `qm list`; row `terminated`; the approval request exists before it | DEV (approval-gated; harness approves the `pg-*` scoped policy) |
| F3 | `promote_replica` (postgres primary → replica, DB VIP cutover, fence) | db-1, db-2, DB VIP, `ReplicaLagSensor` | after stopping db-1: db-2 `pg_is_in_recovery() = f`; the VIP moved; a write through the VIP lands in db-2 | DEV (after inc. 1) |
| F4 | `restore_volume` | D2 | — | NO on `dna` (snapshots) |
| F5 | `relocate_workload` (region to region) | second region | — | NO: one Proxmox region; provable as a same-region blue/green only |
| F6 | `capacity_recommend`, `attribute_failure`, `runbook_generate` | any | output names real instances/promotions; runbook lists the template's real boot order | DEV |

### G. Federation

| # | Capability | Needs | Positive oracle | Status |
|---|---|---|---|---|
| G1 | `sdwan_only` peer: prefix advertisement into AllowedIPs and FIB (`FederationPrefixResolver`) | a plain WireGuard endpoint on the LAN advertising a `/64` | hub's compiled `allowed_ips` carries the prefix; spoke FIB has it; a ping into the prefix is answered by the stand-in | DEV |
| G2 | `platform` federation propose → accept → enrol → heartbeat (`federation_acceptance`, `federation_manager`, `federation_peer_remediate`, `FederationPeerLivenessSensor`, `smoke_test_k3s_federation`) | a second control plane | `FederationPeer` reaches `active` on both sides; liveness sensor emits when the peer is stopped; remediate re-handshakes | OP (16 GB second platform VM on `dna`) |
| G3 | `cluster_member` spawn with PG replication (`smoke_test_cluster_member_ha`) | G2 | replication slot active on the parent | OP |
| G4 | Cross-site SDWAN over a real WAN / NAT | second physical site | — | NO: single LAN; NAT traversal cannot be proven here |

### H. GitOps

| # | Capability | Needs | Positive oracle | Status |
|---|---|---|---|---|
| H1 | Register → sync → drift proposal → apply (`gitops_register_repository`, `gitops_sync_repository`, `gitops_apply_proposal`, `GitopsDriftSensor`) | a repo on `git.powernode.org` describing a `pg-*` template | a commit changing a module assignment yields one `AgentProposal`; applying it changes the live template and the node's `running_module_digests` on the next refresh | DEV |

### I. Supply chain and security

| # | Capability | Needs | Positive oracle | Status |
|---|---|---|---|---|
| I1 | Package repository sync (`package_repository_sync`, `PackageDriftSensor`) | the existing Ubuntu Noble repo | `package_count > 0`, `last_synced_at` set (it has never completed) | DEV |
| I2 | Package → module materialization + build (`package_module_create`, `package_module_refresh`, `discover_packages_by_intent`) | I1 + builder pool | `NodeModule` row with dependency edges; a build task completes with a digest; the module attaches to a `pg-*` node and its binary resolves (A3) | OP (publish auto-promotes; use a `pg-only` module) |
| I3 | Architectures (`architecture_*`, `suggest_architectures_for_fleet`) | any | proposal row; a non-canonical row round-trips | DEV |
| I4 | CVE intake → exposure → remediation (`create_cve`, `cve_response`, `cve_remediation_orchestration`, `cve_runbook_generate`, `smoke_test_k3s_cve_drill`) | a module with a known package list on a `pg-*` node | exposure names the node and module; the orchestration dispatches a rebuild whose new digest lands on the node | OP for the rebuild half (publish); DEV for triage |
| I5 | Honeypot canary (`HoneypotAccessSensor`, `quarantine_honeypot_instance`) | 1 pooled spoke as honeypot | a probe connection emits the signal; quarantine cordons the instance (`cordon` set) | DEV |
| I6 | Module signing / cosign on module mount | — | — | NO: verifier is wired off on all mount paths (standing memory); provable only after that lane is built |

### J. Autonomy, governance, platform ops

| # | Capability | Needs | Positive oracle | Status |
|---|---|---|---|---|
| J1 | **The gate blocks**: a `require_approval` action does not execute | any sensor/action pair on a `pg-*` node (e.g. A8's reboot) | `ApprovalRequest` row exists and the VM's `boot_id` is unchanged until approval; after approval it changes | DEV |
| J2 | `notify_and_proceed` and `auto_approve` lanes | same | outcome row + notification; no approval row | DEV |
| J3 | Kill switch (`kill_switch_status`, `abort_task`) | a running `pg-*` task | task aborted; no further actuation on the node | DEV |
| J4 | Self-management fence (INV-1) | `self_hosting_node_id` set | an actuate path handed ops-hub's instance returns `self_managed_skip` (unit-level, via a dry-run signal) — never a live test against ops-hub | DEV (dry-run only) |
| J5 | Governance/capability gap (`GovernanceGapSensor`, `CapabilityGapSensor`, `governance_gap_propose`, `fulfill_capability_request`) | a declared category with no owner; an NL capability request | one improvement offer; a durable `FulfillmentRequest` reaching a leased `pg-*` instance | DEV |
| J6 | SLO sensors (`ProjectSloSensor`, `SloViolationSensor`), `scale_project`, adaptation lane | a project with replicas in the pool | replica added/removed on `dna` (VM count changes) with provenance-stamped proposal | DEV |
| J7 | Stuck task backlog (`StuckTaskBacklogSensor`) | a task on a stopped node | signal emitted; reaper resolves it | DEV |
| J8 | `platform_maintenance` / `platform_resilience` (cordon, stop, scale) | `pg-*` instance | cordon sets `cordon`; stop changes `qm` status; the same call against ops-hub is refused by the fence (dry-run) | DEV for `pg-*`; NO live against ops-hub (§7) |
| J9 | `platform_deploy` (new sovereign platform) | 16 GB VM | new platform answers `/up` | OP |
| J10 | `TradingPressureSensor` | — | — | NO: trading extension out of scope |
| J11 | Real cloud providers (AWS/GCP/Azure/OpenStack adapters) | credentials | — | NO: adapters are inert (gems never added, standing memory); no credentials |

**Totals:** 72 rows — DEV 46, OP 16, NO 10 (I4 counted as OP for its rebuild half). Every
B row plus C1–C3, C6, D3, E5, F1, F3 and G1 depend on increment 1 (a working overlay).

---

## 5. Topology

```
 ops-hub (VM 600) — control plane only; self_hosting_node_id fence set; never a peer, never a pg-* node
 dev-cell (9000)  — LAN-side client only (curl to DNAT/exposed ports); no WireGuard in its kernel

 Network A (dryrun-fabric, ibgp from inc. 8)         Network B (static)
 ┌──────────┬──────────┬───────────┬───────────┐     ┌──────────┬───────────┐
 pg-hub-a   pg-hub-b   pg-spoke-N  pg-gw-1           pg-hub-a   pg-gw-1
 hub, RR    hub        pool, DR    lan_subnets,      (multi-VRF host)
 A+B        A          victims     NFS export, A+B
 pg-db-1 (postgres-primary, DB VIP)  pg-db-2 (postgres-replica)   pg-k3s-server  pg-k3s-agent  pg-docker  pg-ud-1
```

- Two existing testbed VMs are reused as `pg-hub-a` (9005) and the first `pg-spoke` (9007)
  **after** being reprovisioned onto the new image at tiny size; keeping 16 GB nodes is not
  worth the RAM.
- Every node is `network_profile: lightweight` until phase 3 adds one heavyweight chassis.
- Federation stand-in (G1): a plain WireGuard endpoint on the LAN advertising a `/64`; the
  cheapest host is a `pg-*` node running `wg setconf` on a `wg-fed0` interface (the orphan
  reaper only touches `wg-sdwan-*`).

---

## 6. Lifecycle and reset

- **Provider:** `IPNode PVE` on `dna`. `local-qemu` (`qemu:///session` on the Rails host,
  i.e. ops-hub) is unusable.
- **Create:** `system_create_node` on a `pg-*` template + `system_provision_instance`
  (synchronous; `uefi_disk` imports the promoted image, `proxmox_provider.rb:258,1015,1400,1561`);
  hubs get static `ip_config` (`:860,1417`) so `endpoint_host` survives rebuilds.
- **Reset = rebuild onto the newest promoted image, verified by content.** Spokes, k3s-agent,
  docker and the DR victims come from an `ephemeral` pool (`instance_pool.rb:58`;
  `release!`/`replenish!`/`drain!` at `instance_pool_service.rb:205,335,397`); promotion to
  `ready` already gates on a handshake (`node_instance.rb:631-640,513-520`). Long-lived roles
  (hubs, db, k3s-server, gw) are rebuilt with terminate + provision; the protection flag is
  cleared by the provider (`proxmox_provider.rb:461-469`). The `verify:` netdev probe (inc. 2)
  is what makes "rebuilt onto a capable image" a measured fact rather than a version number.
- **Never**: `qm snapshot`, `snapshot_volume`, `restore_volume_snapshot` on `dna`.
- **Time (measured on the testbed):** instance row → composed node ≈ 85 s; parallel provision
  of 11 tiny nodes ≈ 4 min; phase-1 SDWAN pass ≈ 5–8 min when oracles read timestamps
  directly; a full matrix pass is bounded by K3s install and DR waits, estimate 30–45 min;
  teardown ≈ 2 min. No cloud spend.
- **Bound the churn:** pool `max_size 2`, `warming_timeout_seconds` set, harness fails fast
  when the hub has no handshake.

---

## 7. Observation layer

Rule: every oracle is a value that could not exist unless the plane did the thing. Absence is
a failure, never a skip. Three channels:

- **A. Platform rows written by agents**: `Sdwan::Peer` handshake/counters, `BgpSession`,
  `sdwan_state`, `module_verify_state`, `running_module_digests`, `DockerHost.status`,
  `FlowSample`, `ApprovalRequest`, `FleetEvent`.
- **B. On-node facts via `verify:` probes on the heartbeat.** Today PATH-resolution only
  (`module_verify.rb:95`); increment 2 adds an `exec` kind (command + expected regex/JSON
  path, within the 20 s budget, `evaluator.go:39`). First probes on `sdwan-overlay`:
  `ip link add pg-probe0 type wireguard && ip link del pg-probe0` (netdev creatable — the
  probe that would have caught this on day one), VRF present, handshake age, FIB prefix,
  VIP on `d-sdwan-*`, `nft` chain counters, `findmnt`, `pg_is_in_recovery()`.
- **C. Harness-driven traffic** from a VM-tier seed (`smoke_test_proving_ground.rb`, one
  pass per matrix area, modelled on `smoke_test_k3s_pod_plane.rb` site+): traffic is
  generated by exec probes so the harness needs no shell; the packet oracle is the
  receiver-side counter delta (`peer.rb:398`) sized above keepalive noise.
- **D. Promoted-image capability oracle** (from §1.2): a seed-time check that the promoted
  publication's `git_sha` is an ancestor of the extension ref the running platform was built
  from for every path under `initramfs/`; emits `system.boot_image.capability_lag` when not.
  This is the promoted-vs-code check the drift sensor cannot make.

Every pass emits `FleetEvent`s (as the existing passes do, `docs/SMOKE_TEST.md` event table)
and exits non-zero on any absent oracle.

---

## 8. How it plugs into what exists

| Piece | Existing seam |
|---|---|
| Nodes | `sdwan-testbed-amd64` (renamed/cloned to `pg-*` templates), existing modules `sdwan-overlay`, `postgres-primary/-replica`, `storage-tools`, `dev-cell-docker`, `qemu-guest-agent` |
| Reset | `InstancePoolService`, `ProvisioningService#provision_instance` / `#terminate_instance`, `ProxmoxProvider` |
| Enrollment | `Sdwan::PeerEnroller` (explicit hubs), template `sdwan_network_id` auto-enroll (spokes) |
| Compilers | `TopologyCompiler`, `FirewallCompiler`, `NatCompiler`, `Bgp::*`, `HostBridgeAllocator`, `OvnCompiler` — consumed unchanged |
| On-node oracles | `verify:` probes + `ModuleVerifyStateWriter` + `ModuleVerifyFailedSensor` |
| Platform oracles | `/status/sdwan`, `/status/bgp`, `AgentApplyStateWriter`, the 36 sensors, `recent_signals` |
| Harness | new smoke seeds in `server/db/seeds/` listed in `docs/SMOKE_TEST.md`; run via `rails runner` on the platform |
| Safety | `SelfManagementFence` (SiteSetting), `pg-*` naming, dedicated templates/pool, scoped intervention policies |
| Thresholds | `SiteSetting` (the apply-health seam) |

New runtime code is limited to: the `exec` probe kind, `pve.vm.tiny`, the fence check in the
rollout executor, the capability-lag oracle, the firewall/NAT name fix, and the seeds.

---

## 9. The OVN central-daemon decision

**Scope OVN out of phases 1–2; build it in phase 3 as NodeModules on a dedicated node.**
Nothing provisions northd/NB/SB (`nb_probe.rb` header); no module ships `openvswitch`,
`ovn-host` or `ovn-central`; the chassis applier is host-shaped (`ovn-controller` unit,
`ovs-vsctl` on PATH). Three modules, `nb_db_endpoint`/`sb_db_endpoint` on a fabric VIP,
`NbProbe` treated as `:not_measured` for overlay-only endpoints (it runs from ops-hub, which
is not on the overlay); the agent's `sdwan_ovn_state` is the oracle. Landing OVN before
WireGuard has carried a packet would repeat the "activate a lane nothing observes" pattern.

---

## 10. Sequenced increments

Each leaves the environment more provable than it found it. **Op** marks an operator decision.

| # | Increment | Size | Needs | Newly provable |
|---|---|---|---|---|
| 0 **Op** | Set SiteSetting `self_hosting_node_id` = ops-hub's Node; add the fence to `boot_image_drift_rollout_executor` and `disk_image_promote`; add `pve.vm.tiny`; `pg-*` templates + scoped intervention policies | S | — | J4 (dry-run); the boundary in §3 becomes enforced, not conventional |
| 1 **Op** | Build+promote an amd64 image from develop (carries `fe5c8da4`); build+publish `powernode-system-base` from develop (carries `28460bbb`, `b4f41c35`, `efcc24fa`); reprovision 9005/9007 as tiny `pg-hub-a`/`pg-spoke-1`; explicit hub attach with a static endpoint | S build, fleet-scope | 0 | B1, B2 (first handshake ever); collapses C1/E5/F3 blockers |
| 2 | `exec` probe kind + `sdwan-overlay` probes (netdev creatable, VRF, handshake) + capability-lag oracle | M | 1 | A3, channel B for everything after |
| 3 | Firewall/NAT interface-name fix with a lint spec; investigate `private_ip`/cloud-sync | S | — | B4 |
| 4 | `smoke_test_proving_ground.rb` pass 1 (SDWAN on two nodes): B1–B3, B12, the gate row J1 via A8 | M | 1, 2 | B3, B12, J1, A8 |
| 5 | Spoke pool + `pg-hub-b`, `pg-gw-1`; hub and VIP failover; DR `replace_instance`/`reap_instance` with a volume and VIP on the victim | M | 4 | B7, B8, D1, F1, F2, J2, J3 |
| 6 | `pg-db-1/2`, DB VIP, `promote_replica`, `ReplicaLagSensor` | M | 5 | F3 |
| 7 | `pg-gw-1` NFS export + storage assignment + migration/revert | M | 5 | D3, D4, D5 |
| 8 | Network A → iBGP, route policies, `lan_subnets`; network B multi-VRF; tenant isolation; service discovery VIP | M | 5 | B5, B6, B16, E5 |
| 9 | `pg-docker`, `pg-k3s-server`, `pg-k3s-agent`; delete the six orphan `DockerHost` rows; flannel over SDWAN; drain/reprovision | L | 8 | C1, C2, C3, C6 |
| 10 | `pg-ud-1` user device; port mapping/DNAT with dev-cell; rotation drills; honeypot | S | 5 | B9, B10, B11, I5 |
| 11 | GitOps repo for the `pg-*` templates; package repo sync to completion; architectures; CVE triage | M | 5 | H1, I1, I3, I4 (triage) |
| 12 | Move SDWAN sensor windows onto `SiteSetting`; node-row hygiene (100 leftover builder nodes) | S | — | sensor config completeness |
| 13 **Op** | Module lane on a `pg-only` module: build → publish → smoke-verify → rollback; package→module build; CVE rebuild half; rolling upgrade on the k3s template | L | 9, 11 | A4, C5, I2, I4 (rebuild) |
| 14 **Op** | Boot-image lane scoped to `pg-*`: publish → promote → drift rollout (canary/halt) → rollback → retention | M | 0, 1 | A5, A6 |
| 15 **Op** | Operator-run ingress pass: `Sdwan::Service` local exposure, ACME on LE staging with a real DNS credential, reverse-proxy compose, public TCP | M | 8 | E1–E4 |
| 16 **Op** | Phase 3: `openvswitch-switch` chassis (8 GB), built `sdwan-flow-exporter` + collector; `ovn-host`/`ovn-central` (4 GB) | L | 9 | B14, B15, C7 |
| 17 **Op** | Platform federation: second control plane VM (16 GB), propose/accept/enrol, cluster_member, `platform_deploy` | L | 8 | G2, G3, J9 |

Prerequisite graph: 0 → 1 → 2 → 4 → 5 → {6, 7, 8, 10}; 8 → 9 → 13; 3 before B4; 5 → 11;
{0,1} → 14; 8 → 15; 9 → 16; 8 → 17. Increments 3 and 12 are independent and can go first.

---

## 11. Risks, corrections to the brief, and what I could not verify

**Corrections to numbers and claims supplied in the briefs**

- "~700 GB logical free": `zfs list` shows **606 GB AVAIL** on `local-zfs`. Snapshots: 295, not 296.
- "Stopped/errored CI builders hold RAM reservations": stopped KVM guests hold **no RAM**, only thin disk. The real RAM lever is the **three running builders 9002/9004/9008 (48 GB)** that the pool's `ready 1` does not account for — verify they are not claimed before reclaiming.
- "QGA reply path on dna is broken": from `dna`, `sudo qm guest exec 9005 -- /bin/sh -c …` returned captured output for me on both VMs today (payloads < 120 bytes). Keep payloads small; the channel works.
- "622 MCP actions": the auto catalog has 625 `###` headings. "28 smoke scripts": 34 seed files. "65 executors": confirmed (39+1+5+10+1+5+3+1). "36 sensors": confirmed.
- "Two-node testbed alive": alive, and useless as booted; the template is fine.
- "Thresholds DB-driven": only apply-health. "`verify:` reports on the heartbeat": PATH resolution only. "BGP one network only": stale since IMP-2f34679b6b73. "`sdwan_failover` remediation": planning-only.
- The first team-lead root-cause message (29-minute race) was wrong and its author corrected it; the corrected account matches the on-VM evidence exactly.

**Risks**

- Increment 1 auto-promotes fleet-wide: the new image reaches every node that reboots and the
  new system-base reaches ops-hub immediately (~3 min 502 window). Increment 0 must precede
  it or the first drift-rollout approval can reboot the control plane.
- Pool churn on a dead hub (bounded by `max_size`, warming timeout, fail-fast).
- Heavyweight auto-classification at 4096 MB (explicit `network_profile` on every provision).
- `parse_time` fabrication; firewall tests before increment 3; QGA payload size.
- K3s installs from `get.k3s.io` at runtime (`k3sd/applier.go:137`); if `pg-*` nodes have no
  internet egress, C2/C3 need an egress allowance or a vendored binary.
- Publishing any module auto-promotes; every module-lane row uses a module attached only to
  `pg-*` templates.

**Not verified (read-only limits)**

- Whether `self_hosting_node_id` is set on ops-hub.
- That `10.125.0.201` is 9005's address (team-lead's ARP read says yes).
- Why `private_ip` stays null under `system_cloud_sync`.
- Stored `network_profile` of the testbed instances; pool membership of builders 9002/9004/9008.
- Internet egress from `pg-*` nodes (K3s install, package sync).
- The persisted `sdwan_state.healthy_peers` value (no MCP read of `config`).

---

## 12. Capability families: minimum infrastructure, oracle, RAM, blast radius

Each family answers the same four questions. RAM is on `dna` with the `pve.vm.tiny` (2 GB)
and `pve.vm.small` (4 GB) types from §2.2; "104 GB available" is today's measured headroom.
Blast radius names the three things that must never be a participant: the control plane
(ops-hub), the production fleet (every non-`pg-*` node) and the public mirror
(`github/develop`, which `origin` publishes to).

**The isolation rule for fleet-wide actuators.** Three actuators have no per-target scope:
module publish (auto-promotes to every assignment of that module), disk-image promote (one
default per `NodePlatform`, shared with ops-hub today) and boot-image drift rollout (every
drifted node). The proving ground isolates each by giving it a target that *only* `pg-*`
nodes reference: a **`pg-only` NodeModule** (assigned to `pg-*` templates and nothing else, so
a publish reaches only them); a **second `NodePlatform` named `pg-amd64-uefi`** (`POST
/api/v1/system/node_platforms`, `node_platforms_controller.rb:23`; the webhook already selects
the platform by `platform_name`, `webhooks/disk_image_built_controller.rb:41`) once the amd64
build job takes a platform-name input instead of the literal at
`.gitea/workflows/build-disk-image.yaml:865,928,987`; and a **rollout scoped to instances on
that platform**, behind the fence from §3. Where no such target exists the family says so.

### 12.1 Fleet and capacity

| Question | Answer |
|---|---|
| Minimum infrastructure | one `pg-*` template on `pg-amd64-uefi`; an `ephemeral` pool (`max_size 2`); two long-lived tiny nodes for cordon/drain/replace targets; the existing CI builder pool for `capacity_recommend` density |
| Positive oracle | provision: `booted_image_git_sha` equals the platform default and `running_module_digests` equals the assigned set; cordon: `cordon` set and `mark_pool_ready!` refuses admission (`node_instance.rb:631-640`); drain: `pool_state: draining` and the VM leaves `qm list`; replace: the replacement's `Sdwan::Peer` handshakes and holds the victim's VIP while the victim row is untouched; reap: the victim VM is gone and the `ApprovalRequest` row pre-dates it; pool: `acquire!` returns a member whose `pool_state` flips to `claimed` and `replenish!` creates a `warming` row; silent detection: `system.instance_silent` within `silent_threshold_seconds` of stopping the agent; drift rollout: canary reboots and reports the new sha, batch 2 follows, a failed canary sets `halted: true` |
| RAM | 2 tiny long-lived + 2 tiny pooled = **8 GB** (shared with SDWAN roles) |
| Blast radius | control plane: rollout and reap paths are fenced only once `self_hosting_node_id` is set; production fleet: the pool and templates are `pg-*`; mirror: none. **Boot-image rollout is unsafe until the `pg-amd64-uefi` platform exists** |

### 12.2 Storage

| Question | Answer |
|---|---|
| Minimum infrastructure | `pg-gw-1` with `storage-tools` as the NFS export host; one consumer node on the overlay; two Proxmox volumes for migration |
| Positive oracle | attach: `findmnt` at the requested path on the node and a marker file that survives detach and re-attach on a second node; NFS export: the consumer mounts over `wg-sdwan-1` and the marker round-trips; migration: data present at the target with the assigned owner, the approval row exists before the copy, revert restores the binding; chown retry: the owner uid on the target changes after `storage_chown_retry`; drift: `StorageAssignmentDriftSensor` emits when the on-node assignment is removed |
| Snapshot and restore | **not provable on Proxmox**: `ProxmoxProvider#supports_volume_snapshots?` returns `false` (`proxmox_provider.rb:676`), so `VolumeManagementService#snapshot` declines at the seam (`volume_management_service.rb:305-313`) and `restore_snapshot` never reaches its copy-swap branch (`:480`). Independently, zvol snapshots hang on `dna`. This forces either a second provider with snapshot support or a future NFS-backed copy primitive; neither exists today |
| RAM | gw-1 is shared; consumer is a pooled spoke: **0 GB additional** |
| Blast radius | all volumes are `pg-*` attached; no control-plane path. The NFS export host is a `pg-*` node, never ops-hub |

### 12.3 Container and cluster runtimes

| Question | Answer |
|---|---|
| Real backends today | Docker host provisioning (`docker_provision`, `Devops::DockerHost`), containers, images, services, stacks and swarm clusters are real: core `Devops::Docker::ApiClient`, `SwarmManager`, `StackManager#deploy_stack` (`server/app/services/devops/docker/stack_manager.rb:15`), `NodeManager`. K3s server/agent is real through the agent's `k3sd` (installs from `get.k3s.io`, `k3sd/applier.go:137`). **Inert:** K3s HA control plane (`smoke_test_k3s_ha_control_plane` says not implemented); isolation tiers other than `native` (`System::IsolationTier` maps gvisor/kata/firecracker to runtimes no module ships, `isolation_tier.rb:26-36`); OVN-Kubernetes CNI until §9 |
| Minimum infrastructure | two tiny Docker hosts on the overlay (swarm manager + worker, so promote/demote/drain have a second node); one small K3s server + one tiny agent |
| Positive oracle | `DockerHost.status` leaves `pending`; `docker_list_containers` shows a container the platform started; `docker_list_clusters` shows a swarm with two nodes and `docker_node_drain` moves a service task to the other node; a stack's services reach `replicas 1/1`; `kubernetes_list_nodes` shows two Ready nodes; `tcpdump` on `wg-sdwan-*` carries pod traffic |
| RAM | 2 docker × 2 GB + k3s server 4 GB + agent 2 GB = **10 GB** |
| Blast radius | Docker daemons bind to the overlay `/128`; nothing touches ops-hub. K3s needs internet egress from `pg-*` nodes (unverified) |

### 12.4 Supply chain and CVE

| Question | Answer |
|---|---|
| Minimum infrastructure | the existing `Ubuntu Noble` repository (never synced; `package_count 0`); the CI builder pool; a `pg-only` module target; one `pg-*` node |
| Positive oracle | sync: `last_synced_at` set and `package_count > 0`; package → module: a `NodeModule` row with `ModuleDependency` edges and a build task that completes with a digest; architecture: a non-canonical row round-trips; SBOM/exposure: `create_cve` against a package the `pg-only` module ships yields a `CveExposure` row naming the module version and the `pg-*` node; remediation: `cve_remediation_orchestration` dispatches a rebuild whose new digest appears in the node's `running_module_digests` |
| RAM | reuses the builder pool and one pooled node: **0 GB additional** |
| Blast radius | the rebuild publishes a module version; safe only because the module is assigned to `pg-*` templates alone. Repository sync is account-wide but read-only. Mirror: the module source lives on `git.powernode.org`, not the public mirror |

### 12.5 Module supply chain and release

| Question | Answer |
|---|---|
| Minimum infrastructure | a `pg-only` module (source repo on Gitea, assigned to `pg-*` templates only); the builder pool; two `pg-*` nodes for canary vs rest |
| Positive oracle | build: a `ModuleBuild` completes and `list_module_versions` shows the digest; publish: `current_version_id` moves (memory: read `current_version_id`, never `promotion_state`) and the digest appears on both nodes; rollback: the previous digest reappears; canary: `module_mark_canary` is a decoy (standing memory) — the honest canary oracle is "one node carries the new digest while the second still carries the old", which only a two-template split gives; publication integrity: `module_publication_integrity` reports the artifact sha matching the registry; drift report: `drift_report` names the node whose digest lags |
| RAM | 2 tiny nodes shared with 12.1: **0 GB additional** |
| Blast radius | **publish auto-promotes fleet-wide and the ladder is decorative**, so the only isolation is assignment scope: the harness must refuse any module with a non-`pg-*` assignment before dispatching a build. Building uses the production CI pool (16 GB, acceptable). Mirror: none |

### 12.6 Ingress and certificates

| Question | Answer |
|---|---|
| Minimum infrastructure | a backend on a fabric VIP; a Traefik that is not ops-hub's |
| Finding | **there is no Traefik that is not ops-hub's.** `Sdwan::ServiceExposureWriter` and `Acme::TraefikConfigWriter` write `Core::IngressConfigWriter.default_dynamic_dir` on the Rails host (`traefik_config_writer.rb:59,251`); nodes receive only the federation TCP-forwarder config (`agent/internal/tcpfwd/doc.go`) and `ingress_routes` is a read-only projection (`ingress_routes_controller.rb`). `reverse-proxy-traefik` exists as a module but no writer targets a node's instance of it |
| Positive oracle (when a target exists) | `curl https://<edge>/svc/<slug>` returns the backend marker through ForwardAuth; public SNI reaches the service; an LE-staging certificate row with the requested SAN; renewal changes the serial |
| RAM | 1 tiny `pg-ingress` node running `reverse-proxy-traefik`: **2 GB** (only useful after the writer can target it) |
| Blast radius | **cannot be proven safely today**: every actuator edits the control plane's live ingress. Options: (a) an operator-run pass on ops-hub with a manual revert, or (b) a node-side ingress writer (agent pulls the account's dynamic config for nodes composing `reverse-proxy-traefik`), or (c) the second control plane in 12.10 |

### 12.7 GitOps

| Question | Answer |
|---|---|
| Minimum infrastructure | a repository on `git.powernode.org` describing the `pg-*` templates, modules and pool; no extra node |
| Positive oracle | `gitops_register_repository` row; `gitops_sync_repository` produces a sync run with a non-empty diff and exactly one `AgentProposal`; `GitopsDriftSensor` emits while it is open; `gitops_apply_proposal` changes the live template, and the affected `pg-*` node's `running_module_digests` changes on its next refresh |
| RAM | **0 GB** |
| Blast radius | the repository must describe only `pg-*` resources; `DesiredStateValidator` (`services/system/gitops/desired_state_validator.rb`) should refuse a manifest naming a non-`pg-*` template (small increment). Mirror: the repo is on Gitea, not GitHub |

### 12.8 CI

| Question | Answer |
|---|---|
| Minimum infrastructure | the existing `ci-native-builders-amd64` pool; `provision_ci_worker` for one extra worker during the run |
| Positive oracle | `lease_ci_runner` returns a lease whose instance flips to `claimed` (`ci_runner_lease_service.rb:44-48`) and the Gitea runner registers; a dispatched build (`dispatch_module_build_batch` on the `pg-only` module) reaches `succeeded` with a digest; `release_ci_runner` returns the member to `draining` and the sweep recycles it |
| Dead builders | today: 11 instance rows in `error`, 4 `stopped`, and VMs 9004/9008 running with **no platform row**; 9002 is a running VM whose row is `error`; `ops-cell` (9003, 16 GB) is `starting` with no heartbeat since 08-10. Reaping is approval-gated and an operator decision; the proving ground does not depend on it but the RAM does |
| RAM | pool `target_size 1` = **16 GB** (existing) |
| Blast radius | builders are production CI; a leased builder is isolated by the lease. None of this touches ops-hub |

### 12.9 The autonomy plane

| Question | Answer |
|---|---|
| Minimum infrastructure | any `pg-*` node under a sensor that fires on a real condition; a `pg-*`-scoped intervention policy per lane |
| Positive oracle | sensor: a `FleetEvent` with the sensor's fingerprint after the condition is created (stop the agent, unassign a module, delete a peer); gate: for `require_approval` an `ApprovalRequest` exists and the node's `boot_id`/state is unchanged until approval, then changes; for `notify_and_proceed` an outcome row and no approval row; consent budget: the N+1th decision in 24 h for the module returns `allowed: false` (`consent_budget_service.rb:15-22`) and no actuation follows; executor reach: the actuator's own artefact (a rebooted `boot_id`, a moved VIP, a reattached module); campaign machinery: `campaign_propose` → approve → `campaign_start` → an increment recorded against a `pg-*` change; dev-loop: `dev_next_task` hands out a task whose completion is recorded by `dev_complete_task` |
| RAM | **0 GB** additional |
| Blast radius | the DecisionEngine is account-wide; scoping policies to `pg-*` actions (§3 rule 5) is the boundary, and the fence is the backstop. The one autonomy test that must stay dry-run is the fence itself (J4) |

### 12.10 Multi-tenancy and isolation

| Question | Answer |
|---|---|
| Minimum infrastructure | a second `Account` (`POST /api/v1/accounts`, platform-tier `super_admin` permission, `accounts_controller.rb:3-12`); a user in it; one `pg-*` node in each account |
| Positive oracle | negative: account B's user calling `system_list_instances`, `sdwan_list_networks`, `list_volumes` sees none of account A's rows, and `system_get_instance` with an account-A id returns not-found; positive: B provisions its own node and sees only it; isolation tiers: `native` runs; `gvisor`/`kata`/`firecracker` refuse with the missing-runtime reason; data residency: `sdwan_set_data_residency` needs a `FederationPeer`, so it rides 12.11 |
| Account isolation as the proving-ground boundary | the strongest possible boundary, because every sensor and executor is account-scoped, but expensive: providers, templates, pools **and modules** are account rows (`system_node_modules.account_id NOT NULL`, core `schema.rb`), and the platform-module loader runs only at first boot (standing memory), so a second account would need its own provider connection and a rebuilt module catalog. Recommendation: `pg-*` templates + fence in the same account for phases 1–2; measure the catalog cost before choosing account isolation |
| RAM | 1 tiny node in account B: **2 GB** |
| Blast radius | creating an account is a tenancy boundary with an audit row; reversible. No control-plane path |

### 12.11 What needs a second control plane or a second Proxmox host (findings, not blockers)

- **Platform federation** (propose/accept/enrol/heartbeat, cluster_member with PG replication,
  `platform_deploy`): a second control plane VM, 16 GB, on `dna`. `sdwan_only` federation is
  provable without it (G1).
- **Ingress** (12.6) unless the node-side writer is built.
- **Cross-region relocate and failover** (`relocate_workload`, region-aware scale): a second
  Proxmox host registered as a second region. `local_qemu` is not a substitute (it is ops-hub).
- **Volume snapshot/restore** (12.2): a provider with snapshot support, i.e. not Proxmox as the
  adapter stands, regardless of the `dna` wedge.
- **Real WAN / NAT traversal, bare metal, arm64, real cloud adapters**: outside `dna` entirely.

---

## 13. Environment shape

| # | Instance | Type / GB | Pool | Host | Purpose |
|---|---|---|---|---|---|
| 1 | `pg-hub-a` (rebuild of 9005) | tiny / 2 | long-lived | dna | SDWAN hub, RR, member of nets A and B |
| 2 | `pg-hub-b` | tiny / 2 | long-lived | dna | second hub, hub failover |
| 3 | `pg-gw-1` | tiny / 2 | long-lived | dna | gateway (`lan_subnets`), NFS export host, net B |
| 4 | `pg-db-1` | small / 4 | long-lived | dna | postgres-primary, DB VIP |
| 5 | `pg-db-2` | small / 4 | long-lived | dna | postgres-replica, `promote_replica` target |
| 6 | `pg-k3s-server` | small / 4 | long-lived | dna | K3s server, flannel over SDWAN |
| 7 | `pg-k3s-agent` | tiny / 2 | ephemeral pool | dna | agent join, drain/reprovision |
| 8 | `pg-docker-1` | tiny / 2 | long-lived | dna | swarm manager, stacks, services |
| 9 | `pg-docker-2` | tiny / 2 | long-lived | dna | swarm worker, node promote/drain |
| 10 | `pg-ud-1` | tiny / 2 | long-lived | dna | user-device role, federation stand-in (`wg-fed0`) |
| 11–12 | `pg-spoke-N` | tiny / 2 × 2 | ephemeral pool (`max_size 2`) | dna | DR victim + warm spare, honeypot, churn |
| 13 | `pg-tenant-b-1` | tiny / 2 | long-lived, account B | dna | tenancy negative oracle |
| — | `ci-native-builders-amd64` | large / 16 | existing pool | dna | module and image builds (unchanged) |
| **Phase 1–2 total** | **13 new instances** | | | | **32 GB new + 16 GB existing = 48 GB of the 104 GB available** |
| Phase 3 | `pg-ovs-1` medium / 8, `pg-ovn-central` small / 4, `pg-ingress` tiny / 2, second control plane large / 16 | | | dna | OVS/IPFIX, OVN, node-side ingress, platform federation: **+30 GB** |

Not on the roster, by design: ops-hub, dev-cell (LAN-side client only), ops-cell, VM 300.
Two `Sdwan::Network`s (A ibgp, B static), one second `NodePlatform` (`pg-amd64-uefi`), three
`pg-*` templates (hub/gateway, pooled spoke, db), one `pg-only` module, one GitOps repository,
one second account.

---

## 14. Increments for the wider ground

SDWAN increments are referenced by their §10 numbers and not restated. **Op** marks an
operator decision.

| # | Increment | Size | Needs | Newly provable |
|---|---|---|---|---|
| W0 **Op** | §10 #0 plus: `pg-amd64-uefi` NodePlatform, `platform_name` input on the amd64 image job, `pg-only` module skeleton, harness refusal of non-`pg-*` targets and of modules with non-`pg-*` assignments | S | — | the isolation rule in §12 becomes enforceable |
| W1 **Op** | §10 #1 (image + system-base rollouts) | — | W0 | B1, B2; unblocks C1, E5, F3 |
| W2 | §10 #2–#4 (exec probes, name fix, SDWAN pass 1) | — | W1 | A3, B3, B12, J1, A8 |
| W3 | §10 #5 with the DR drill: pool, replace, reap, cordon, drain, silent instance, consent budget | M | W2 | 12.1, J2, J3, J5–J7 |
| W4 | §10 #6–#7: db pair + promote_replica; NFS export, migration, chown | M | W3 | 12.2 (except snapshot), F3 |
| W5 | §10 #8–#9 plus the second Docker host: swarm, stacks, services, K3s | L | W3 | 12.3 |
| W6 | GitOps repo + validator scope guard; package sync to completion; architectures; CVE triage | M | W3 | 12.4 (triage), 12.7 |
| W7 **Op** | Module lane on the `pg-only` module: build → publish → integrity → drift report → rollback with the two-template canary split; package→module build; CVE rebuild | L | W5, W6 | 12.5, 12.4 (rebuild), 12.8 |
| W8 **Op** | Boot-image lane on `pg-amd64-uefi`: publish → promote → scoped drift rollout → rollback → retention | M | W0, W1 | A5, A6 |
| W9 **Op** | Second account + tenant node; negative oracles; isolation-tier refusals | S | W3 | 12.10 |
| W10 | §10 #10–#12 (user device, DNAT, rotation, honeypot, sensor windows, node hygiene) | — | W3 | B9–B11, I5 |
| W11 **Op** | Ingress: choose (a) operator-run pass on ops-hub with manual revert, or (b) node-side ingress writer + `pg-ingress`; ACME on LE staging with a DNS credential | M–L | W4 | 12.6 |
| W12 **Op** | §10 #16–#17 (OVS/IPFIX, OVN, second control plane, platform federation, `platform_deploy`) | L | W5 | B14, B15, C7, G2, G3, J9 |

Prerequisite graph: W0 → W1 → W2 → W3 → {W4, W5, W6, W9, W10}; {W5, W6} → W7;
{W0, W1} → W8; W4 → W11; W5 → W12.

---

## 15. Additional unverified items for the wider ground

- Whether `pg-*` nodes have internet egress (K3s install, package sync) — the platform's own
  egress is default-deny; the fleet's is unknown.
- Pool membership of VMs 9002/9004/9008 and the state of `ops-cell` (9003) before any reclaim.
- Whether the amd64 disk-image job can be parametrised without breaking the OCI push path
  (only the three literal sites were read).
- The cost of rebuilding the module catalog for a second account (content-addressed build
  skip may make it cheap; not measured).
- Builder 9010 reports `agent_version: system-disk-image/v1.0.0` while every other node reports
  `dev`; which artifact stamped it was not traced.

---

## Top three decisions for the operator

1. **Approve the two rollouts and the fence first**: set `self_hosting_node_id`, then build
   and promote a post-`fe5c8da4` amd64 image and publish a post-`28460bbb` system-base.
   Nothing in SDWAN, Docker, K3s-over-SDWAN, service discovery or DB failover is provable
   until both land, and the fence is what keeps the resulting fleet-wide drift from rebooting
   ops-hub.
2. **Add `pve.vm.tiny` (2 GB) and size the proving ground at 11 nodes / 28 GB**, explicit
   lightweight profile, `pg-*` templates and pool; do not reuse 16 GB nodes; reclaim the three
   apparently orphaned running builders only after verifying pool membership.
3. **Accept the "not provable here" list** (zvol snapshots/restore on `dna`, K3s HA, bare
   metal, arm64, real WAN federation, real cloud adapters, live actuation against ops-hub) and
   fund phase 3 (OVS/OVN/IPFIX modules, second control plane) as separate approvals.

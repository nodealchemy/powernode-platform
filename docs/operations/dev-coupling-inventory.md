# Dev-plane coupling inventory (living)

**Purpose:** enumerate everything that would break if `dev` (VM 300 on dna, `dev.ipnode.us`,
`10.125.0.22`) were switched off. Feeds RCP **P7** and
[dev-methodology-post-dev-plane.md](./dev-methodology-post-dev-plane.md).

**Why this exists:** two of the first four couplings found had **already rotted silently** — CI
was pinned to an address dev stopped using, and nobody knew until a build was dispatched. A
one-shot "turn dev off and see" at the end of P7 would surface these as outages under time
pressure with the fallback already gone. Find them by *disuse* instead.

Started 2026-07-25. **Not complete** — absence from this list is not evidence of absence.

## Good news first

`dev.ipnode.us` / `10.125.0.22` / `dev.powernode*` appear **nowhere** in `.gitea/workflows/`,
`modules/`, or `initramfs/` — verified by grep. Nothing is baked into source or images. Every
coupling found so far lives in **mutable config** (Gitea Actions secrets, platform settings),
which means the migration surface is small and centrally changeable rather than requiring
rebuilds.

## Findings

| # | Coupling | Where | Impact if dev dies | Status |
|---|---|---|---|---|
| 1 | CI `POWERNODE_API_BASE` pinned to `10.125.0.232` — dev's **former** IP | Gitea secret | CI already broken; failed silently | ✅ **fixed** → `https://ops-hub.ipnode.us` |
| 2 | `ops.powernode.org` resolves to a host that **doesn't serve the platform** — yet it is the workflow's hardcoded default. Re-checked 2026-08-01: now resolves `10.125.1.32` (the git HTTPS proxy), `/up` connection-refused | DNS + `build-disk-image.yaml:390,551` | CI silently falls back to a dead host whenever the secret is unset | ⚠️ **still open** — needs a DNS record or the default changed |
| 3 | **CI builders enrol to dev**: `SiteSetting[system.ci_builder.enroll_platform_url] = https://dev.ipnode.us` | platform setting | **Build fleet cannot enrol.** You lose the ability to build the images needed to fix it — the circular dependency P7 exists to break | ✅ **fixed** — verified 2026-08-01 on ops-hub: `https://ops-hub.ipnode.us` (+ `enroll_ca_pem` present, no dev reference) |
| 4 | `POWERNODE_DISK_IMAGE_WEBHOOK_URL` — the call that creates the `DiskImagePublication` | Gitea secret (value masked) | New images publish to the wrong plane. Strongly implied by dev's DB holding the current publications | 🔴 open — **repoint with #1 or CI is split-brained** |
| 5 | `reverse_proxy_url_config.trusted_hosts` includes `dev.powernode.org` / `dev.ipnode.us` | AdminSetting | Cosmetic; stale entries only | minor |

### Note on #4 — a self-inflicted split

Repointing #1 to ops-hub while #4 still points at dev leaves CI **half-migrated**: it fetches
registry config and authenticates against ops-hub, then announces the finished image to dev.
Either repoint both or neither. This is exactly the failure mode the "name things, never pin
addresses" rule is meant to prevent, and it was introduced *by the migration itself* — worth
recording as evidence that partial cutovers are their own hazard.

## Findings from actually provisioning a dev-cell (2026-07-25)

Proving the replacement workflow surfaced four more, none visible on paper. A cell *was*
successfully provisioned, promoted and shelled into — ruby 3.2.8 (exact match to dev), node 24,
its own PostgreSQL 16, git, tmux, Claude Code 2.1.216, passwordless sudo, 15 GB RAM, Gitea
reachable. The environment is genuinely capable. What was broken was everything around it.

| # | Finding | Impact |
|---|---|---|
| 6 | **Pool promotion was permanently blocked.** The `powernode-dev-cell` template pins `sdwan_network_id` to an SDWAN network named **`dev-fleet`** that has no hub — fleet-wide `Sdwan::Peer` count was **0** before tonight. `sdwan_overlay_ready?` gates promotion on a WireGuard handshake that can never happen, so cells sat `warming` forever and `acquire_pooled_instance` would never return one. **Almost certainly why the pool sat at `target_size: 0` — it never worked.** Unblocked by deleting the two dead peer rows; both promoted within one heartbeat. Contradicts the standing "SDWAN preferred, not required" directive. |
| 7 | **`git clone` fails from a cell — no credentials.** A cell cannot fetch source, which is the whole point. Needs a Gitea deploy token (Vault-backed). |
| 8 | **Operator access not wired for pool cells.** Pool-created nodes carry no `config["authorized_keys"]`, so cells accept only account-user keys, not the deploy key. Works today by luck of an account key matching. |
| 9 | **Cell provisioning depends on `dna-data`** — cidata ISOs are staged on the NFS export whose blip caused the 2-day outage. Making the dev workflow depend on it reintroduces that fragility one layer up. |

Plus two non-coupling defects worth tracking: the pool **over-provisions** (manual replenish races
the 60s reaper; both compute the same deficit, and it corrects shortfalls but not surpluses), and
**`go` is absent** from the cell image, so a cell cannot build the agent — exactly the work that
exposed all of this.

**And the CI target has its own TLS problem:** pointing CI at ops-hub now fails with
`curl: (60) SSL certificate problem: self-signed certificate`. ops-hub serves its own self-issued
cert; dev has a real Let's Encrypt one. Publishing to ops-hub needs either its CA in the runners'
trust store or a trusted cert on ops-hub.

## Finding from delivering a module to ops-hub (2026-07-26) — **BLOCKER**

| # | Finding | Impact |
|---|---|---|
| 10 | **ops-hub's boot composition is frozen to a 2026-07-19 LKG whose `source` is `https://dev.ipnode.us`**, listing DEV's module IDs. `/persist/var/lib/powernode/assignment-lkg.json`. | 🔴 **Blocks dev-off.** Worse, it can never self-correct: `ComposeForPivot` fetches the assigned-module set **pre-pivot**, and ops-hub *is* its own platform, so the fetch always fails → every boot sets `from_lkg: true` → `LKGCapturer.Run()` returns early on exactly that condition → the LKG is never re-captured. `current_version` changes cannot reach this node at all. The documented refresh path (delete the file, let the next healthy boot recapture) **bricks** it: no LKG + unreachable platform = nothing to compose. |

This one was invisible to a config audit because it lives in **on-node state**, not in a setting or
a secret — a reminder that "find couplings by disuse" must include the nodes' own persisted state,
not just the control plane's tables. Worked around on 2026-07-26 by retargeting the LKG through the
agent's own `WriteBootLKG` (checksum is `sha256(json.Marshal(Modules))`, so a hand-edit is rejected);
a supported re-freeze mechanism is still needed.

## Findings from live traffic analysis (2026-08-01, dev-plane-retirement campaign)

Context: dev's `powernode_development` DB was mass-deleted 2026-07-30 ~17:35–18:02, so **every
registry row for anything dev-enrolled is gone** — any node whose platform was dev is now
permanently orphaned (its identity cannot be looked up even though its cert may verify).

| # | Coupling | Where | Impact if dev dies | Status |
|---|---|---|---|---|
| 11 | **Dev's traefik still serves `Host(ops-hub.ipnode.us)` routers** (`acme-…0b83….yaml`, regenerated 07-29) — dev answers as ops-hub for any client with stale DNS or a pinned keep-alive connection | dev dynamic config | Misleading: an operator browser tab on "ops-hub" can actually be dev's Vite (observed live from the workstation, ~6.9k req/hr). All API traffic through it 4xxes since the wipe | ⚠️ open — dies naturally at dev-off; meanwhile close stale tabs, check workstation `/etc/hosts` |
| 12 | **Six orphaned fleet agents poll dev every ~30 s** (403/401): `ci-native-builders-amd64-pool-*` at .194/.205/.223 and `ci-builders-amd64-pool-*` at .213 — all provisioned 2026-07-30 ~16:10–17:20 UTC, **minutes before the wipe** — plus .217 (= VMID 503, a 5th from 07-29) and stillborn VMID 505 (provisioned at the wipe-start minute) | LAN VMs (MAC OUI 12:25:78, platform-assigned) | Wasted dna capacity; after any reconnect they would have moved their 401 noise to the real ops-hub | ✅ **ALL SIX destroyed 2026-08-01** (two operator approvals; MAC-verified to dna VMIDs 500/501/502/503/504/505; freed 96 GB RAM / 960 GB disk). Only ops-hub-b (#13) still reaches dev |
| 13 | **`ops-hub-b` (.220) is alive** = **VMID 601 on PVE cluster node `rna`** (`ops-hub-b-instance-20260727044326`, provisioned 07-27 04:43 via platform naming — by dev's platform for RCP P1a, so the wipe destroyed its registry row; the "not yet created" RCP docs were stale snapshots, not evidence of gate-jumping). `rcp-watchdog` VM 9001 is also on rna. PVE is a 4-node cluster (dna .10 + .11/.12/.13) | RCP campaign asset | Unmanaged control-plane instance, 5+ days of /persist state, no registry row anywhere | parked → RCP campaign: re-enroll to ops-hub or re-provision at P1a resume (do NOT auto-dispose) |

Note on #12: the pool provisioning timestamps put **active CI-pool provisioning on dev inside the
wipe window** — whatever session drove that activity is the best lead for the wipe's root cause.

**2026-08-01 DB-side scan of ops-hub: CLEAN.** Zero `dev.ipnode`/`10.125.0.22` hits across
`site_settings`, `system_gitops_repositories`, `system_package_repositories`,
`system_federation_peers`, `system_node_platforms.disk_image_oci_ref`,
`system_disk_image_publications.oci_ref`, and all CI workflow files (core + extensions/system +
agent/initramfs/module-repo). None of the six orphan IPs match any `system_node_instances` row —
**ops-hub has no knowledge these VMs exist**. The residual coupling class is exactly what a DB scan
cannot see: per-node on-disk agent state (`platform_url`, pinned connections).

**Escalation on #13:** `docs/operations/rcp-p1a-ops-hub-b-provisioning-design.md` and the RCP
campaign handoff both state ops-hub-b is **design-only, gated, "not yet created"** — yet a live
host answers to that name at .220 with a populated `/persist`. Either something jumped the RCP
gate or an unrelated VM took the name. Provenance needs dna/Proxmox access (currently denied from
dev — see below). Operator decision required; do not auto-dispose.

## Still to check

- ~~dna SSH denied~~ **RESOLVED 2026-08-01**: dna accepts `admin` with the **powernode-deploy**
  key (`ssh -i ~/.ssh/powernode-deploy admin@dna`; default id_ed25519 is not authorized; `qm`
  needs `sudo -n`). Watchdog verified live the same day: `powernode-fleet-watchdog.timer` clean
  30 s cadence + `powernode-ops-hub-qmstart-retry.timer` armed. Remaining dna item: ops-hub-b is
  NOT on dna — find which hypervisor hosts it.
- **Gitea Actions secrets** — 11 exist; values are masked by the API, so `POWERNODE_AGENT_BINARY_URL`,
  `PLATFORM_READ_TOKEN` and `POWERNODE_CI_WORKER_TOKEN` scoping cannot be confirmed by inspection.
  They must be verified by *use* (run a build with dev off) or rotated deliberately.
- **CI runner registration** — which platform the Gitea runners themselves are registered against.
- **DNS** — every record pointing at `10.125.0.22`, and who serves that zone.
- **Vault** — AppRole bindings and policies scoped to the dev instance.
- **The anchor's own host** — Gitea is a separately-managed docker container
  ([confirmed off both dev and ops-hub](./dev-methodology-post-dev-plane.md)), so whichever host
  runs it is now load-bearing for every rebuild path and is **not** covered by the ops-hub
  watchdog armed on 2026-07-25. Nothing is watching the anchor.
- **`/opt/powernode` itself** — the live checkout is both the working tree and the running
  platform. Anything reading it by path (scripts, cron, systemd units on other hosts) is a
  coupling.

## Method

Prefer **disuse over destruction**: stop using dev while it still runs, so each discovery is
friction with a fallback rather than an incident without one. Only once nothing has needed dev
for a while should it be powered off for a scheduled, abortable window — and only then
decommissioned.

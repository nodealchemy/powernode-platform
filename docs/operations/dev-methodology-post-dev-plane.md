# Development & management methodology after the dev plane

**Status:** design, 2026-07-25. Feeds RCP v2 **P7** (retire the dev box).
Grounded on live recon, not assumption — verified facts are marked ✅.

## The goal

Operator opens a Claude session, gets a disposable full-power workspace, does the work,
throws the workspace away. No pet machine. Nothing irreplaceable.

## The three failure modes this must avoid

1. **Self-reference.** If the thing that provisions your workspace is the thing your
   workspace exists to repair, you have rebuilt the frozen-LKG trap in a new costume.
2. **A slow inner loop.** Today `/opt/powernode` *is* the running platform: edit → reload →
   observe in seconds. Naively routing every edit through build → publish → compose turns
   that into minutes, and you will feel it on every one-line fix.
3. **Hidden couplings to dev.** Real example, found 2026-07-25: disk-image CI had
   `POWERNODE_API_BASE` pinned to `10.125.0.232`, dev's *former* address. It broke silently
   when dev's IP drifted to `10.125.0.22` and nobody noticed until a build was dispatched.
   There are almost certainly more.

---

## 1. The anchor — what must survive everything

The anchor is the set of things you can rebuild from when everything else is gone. It must
be small, boring, and *not* participate in the system it rebuilds.

| Anchor component | Where | Verified |
|---|---|---|
| Hypervisor | Proxmox cluster `ipnode` (dna/fna/lna/rna) | ✅ live |
| Source of truth | Gitea `git.powernode.org` → **10.125.1.37**, a separately-managed docker container. Distinct subnet from dev (10.125.0.22) and from ops-hub (10.125.0.227 = VM 104); no gitea unit on dev; not a VM in the Proxmox cluster inventory | ✅ **off-dev AND off-ops-hub** (operator-confirmed) |
| Secrets | Vault `vault.ipnode.org` (unsealed, v1.15.6) | ✅ reachable, survives dev |
| Golden image | `DiskImagePublication` for `ubuntu-24.04-amd64-uefi`, content-addressed in the OCI registry | ✅ exists |

**Anchor check: CLOSED.** Gitea is independent of both dev and ops-hub — verified by address
(10.125.1.37, distinct subnet from both), by absence from the Proxmox cluster VM inventory,
and confirmed by the operator as a separately-managed docker container. The source of truth
therefore survives the loss of either plane, which is what makes everything below viable.

**Residual to name, not to fix now:** Gitea's availability inherits from whichever docker host
runs that container. That host is now part of the anchor by definition, and deserves the same
treatment as the rest of it — known, boring, and not dependent on the platform. Worth an
explicit note in the coupling inventory (§6) so "the anchor" never quietly means "a container
nobody is watching."

**Rule: the anchor never depends on the platform.** Proxmox does not need ops-hub. Gitea does
not need ops-hub. Vault does not need ops-hub.

---

## 2. Two execution modes — this is what protects the inner loop

The single most important distinction, and the answer to failure mode (2):

| | **Source mode** | **Composed mode** |
|---|---|---|
| Who | dev-cells | ops-hub, fleet nodes |
| Code | git checkout, Rails dev-reload, Vite HMR | signed erofs modules, overlayfs union |
| Loop | **seconds** | minutes, A/B boot + rollback |
| Lifetime | hours, disposable | durable, versioned |
| Purpose | iterate | run |

**The module/compose/disk-image pipeline is a promotion path, not an iteration path.** It is
*supposed* to be slow and gated — that is what makes it safe to point at a control plane.
Iteration never touches it.

This is not aspirational. The `powernode-dev-cell` template already carries exactly the right
module set ✅:

```
powernode-system-base   base-os-ubuntu-noble
runtime-ruby            runtime-node        ← run Rails + Vite from source
postgres-primary        ← every cell gets its OWN database
claude-tmux             ← the Claude session host
dev-cell                qemu-guest-agent
```

`postgres-primary` per cell is a genuine *improvement* over today: it removes the
shared-test-DB contention that currently forces per-worktree `TEST_ENV_NUMBER` juggling and a
global I/O lock during concurrent DB prep. One cell, one database, no coordination.

---

## 3. Provisioning authority — this is what kills the self-reference

**Cell provisioning is a capability of the anchor, not of ops-hub.**

```
        ┌────────── ANCHOR (must not depend on the platform) ──────────┐
        │   Proxmox API   ·   Gitea   ·   Vault   ·   golden image     │
        └───────┬──────────────────────────────────────────────────────┘
                │ provision-cell  (thin, dependency-minimal)
                ▼
           ┌─────────┐        work happens here
           │ dev-cell│◄─── operator ssh + claude-tmux
           └────┬────┘
                │ promote: build module → sign → publish
                ▼
           ┌─────────┐
           │ ops-hub │  fleet control plane · knowledge/MCP plane
           └─────────┘
```

ops-hub **may** expose "give me a cell" as an MCP tool for convenience. It must never be the
only path. The authoritative mechanism is Proxmox + golden image + identity injection, and it
must be runnable from anywhere holding Proxmox credentials — a cell, ops-hub, or a laptop.

**Consequence:** ops-hub down → you still get a working cell. The circle is cut.

**Do not** make ops-hub the operator's ssh entry point. Enter a *cell*. ops-hub is
infrastructure you manage, not the desk you sit at.

### Degradation contract (state it, then test it)

> A dev-cell MUST be able to clone, build, test and commit with ops-hub unreachable.
> Losing ops-hub costs only knowledge/MCP enrichment — never the ability to work.

MCP and the knowledge graph are advisory. Nothing that compiles or tests may hard-depend on
them. This is the invariant that keeps the workbench independent of the thing it repairs.

---

## 4. Cattle and pets — what you are allowed to lose

| Thing | Class | Survival mechanism |
|---|---|---|
| The cell VM, its OS, its Postgres | **cattle** | rebuild from golden image |
| Committed code | anchor | Gitea |
| Secrets | anchor | Vault |
| **Uncommitted work in flight** | **the only real pet** | see below |
| Claude session context | accepted loss | plans/memory under `~/.claude`, campaign ledger |

Uncommitted work is the one thing that genuinely dies with a cell, and it is the reason
people quietly turn cattle back into pets. Handle it explicitly:

- **v1 (do this now):** cells auto-push a WIP branch to Gitea on a timer and on idle. Cheap,
  needs nothing new, and Gitea is already the anchor. Losing a cell costs minutes, not work.
- **v2 (only if v1 chafes):** attach a small durable workspace volume that follows the
  operator between cells. The machinery exists (`ProviderVolume`, attach/detach) but is
  effectively unused today (`StorageAssignment=0` ✅), so this is greenfield — don't build it
  until v1 demonstrably hurts.

---

## 5. Latency and cost — the two things that make people abandon ephemerality

**Latency.** A cold provision is minutes; that is too slow to reach for casually. The fix
already exists and is simply switched off: **`dev-cell-pool` exists with `size=0`** ✅. Set it
to 1–2 pre-warmed cells and `acquire_pooled_instance` returns in seconds. Pre-warm is what
makes "throw it away" psychologically free.

**Cost.** An always-on `claude-tmux` burns API credits continuously — this has bitten before,
hence launcher-default-OFF. Ephemerality is the fix, provided it is enforced rather than
remembered:

- every cell carries a **TTL** and an **idle reaper**
- the pool auto-replenishes, so reaping is cheap
- the default is OFF; a cell is started because work exists, not in case work appears

---

## 6. Killing the hidden couplings — strangle, don't cut over

A one-shot "dev off" dry-run at the end of P7 is the *worst* way to find couplings: every
discovery is an outage, under time pressure, with the fallback already switched off.

**Invert it. Stop using dev before you stop running dev.**

1. **Now:** stock `dev-cell-pool`, do all new work in cells. dev keeps running, idle, as a
   safety net. Couplings surface as friction, not as outages, and you can always fall back.
2. **Then:** schedule a recurring window where dev is powered *off* for an hour. Anything
   that breaks is a coupling; fix it and repeat until boring. This is a rehearsal you can
   abort, not a migration you must finish.
3. **Then:** dev is already unused and proven-unnecessary. Decommissioning is bookkeeping.

**Standing rule that would have prevented the CI incident: name things, never pin addresses.**
DNS names, not IPs, in every secret, manifest, config and `platform_url`. The CI break was a
pinned IP that rotted silently; it was fixed by pointing at `https://dev.ipnode.us` instead of
chasing the new address.

**Targets for the coupling inventory** (do this as a real increment, not ad hoc): Gitea Actions
secrets, CI runner registration, DNS records, Vault policies and AppRole bindings,
`platform_url` values baked into images, `POWERNODE_*` env in composed units, MCP endpoints,
and anything resolving to `10.125.0.22`.

---

## 7. What ops-hub is actually for

Narrowing this is what makes the whole thing coherent:

- fleet control plane for production nodes
- knowledge / MCP plane
- CI orchestration target and publication registry
- *convenience* cell provisioner — never the authoritative one

And ops-hub is itself cattle: deployed from the same golden image + module pipeline, with A/B
boot and below-payload rollback (proven on hardware 2026-07-25). It is not special. It is
just the node currently holding the control-plane role — which is exactly what RCP's floating
control-plane role (P3) formalises.

---

## 8. Sequenced plan

| # | Step | Depends on | Notes |
|---|---|---|---|
| 1 | Verify Gitea is not co-resident with ops-hub | — | anchor check; everything rests on it |
| 2 | Create the `protected_egress_hosts` SiteSetting | operator | capability already shipped (CI run 1316, 2026-07-21); only the config row is missing |
| 3 | Deliver the fixed boot image to ops-hub | A/B rollback fix | ops-hub currently runs the bricking upgrade path |
| 4 | Stock `dev-cell-pool` (size 1–2) + TTL/idle reaper | 2 | turns ephemeral from painful to free |
| 5 | Make `provision-cell` runnable from the anchor alone | 2 | this is the step that cuts the circle |
| 6 | WIP auto-push from cells to Gitea | 4 | protects the only real pet |
| 7 | Switch default workflow to cells; dev idles | 4,5,6 | strangler begins |
| 8 | Coupling inventory + recurring dev-off window | 7 | rehearsal, abortable |
| 9 | Decommission dev | 8 clean | bookkeeping by then |

Steps 1–3 are prerequisites already in flight or operator-gated. Steps 4–6 are small, because
the primitives exist. Step 7 is a decision, not an engineering task.

## Why this survives the three failure modes

1. **Self-reference** — provisioning authority lives in the anchor; ops-hub is convenience
   only; the entry point is a cell, not ops-hub; the degradation contract is explicit and
   testable.
2. **Slow inner loop** — untouched. Source mode keeps seconds-level iteration; the slow
   verified pipeline is reserved for promotion, where slowness is a feature.
3. **Hidden couplings** — surfaced by disuse rather than by outage, under a
   names-never-addresses rule, with an abortable recurring rehearsal instead of a one-way cutover.

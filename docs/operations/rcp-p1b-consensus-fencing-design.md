# RCP P1-b — Consensus Group + Fencing (Design)

> **Status: DRAFT — DESIGN ONLY. Not approved for execution. No live corosync/HA change.**
> This is a boot-critical / control-plane design, **gated by INV-8** (independent adversarial
> review by a different model/architecture) before any part executes against real hardware.
> **Also gated behind P0's rollback-proof gate (P0-b), which is NOT yet closed** — implementation
> of this increment does not begin until that gate passes, same as P1-a's actual provisioning.
>
> - Campaign: Resilient Control Plane (RCP) v2 — `019f9250-a199-7819-ace6-cee904116b3e`
> - Increment: **P1-b — Consensus group + fencing** (`[Opus]`)
> - Prerequisite: **P1-a** (ops-hub-B healthy on rna/`local-data`) — sibling task, in flight
> - Author: Opus design subagent, 2026-07-24
> - Invariant source of truth: `~/.claude/plans/campaign-reciprocal-control-plane.md` (INV-6, INV-7)
>
> **Mechanism decided by operator (2026-07-24):** the **lighter, lease-based option** — Proxmox HA
> for VM liveness + a 2-member+witness quorum electing the active plane, enforced through the
> existing `System::Autonomy::ControlPlaneFence`. **INV-7 is met in intent, not literally** — see
> §2, documented honestly and without overstating compliance. The heavier literal-INV-7 path
> (guest Pacemaker + STONITH + `priority-fencing-delay`) was **declined** and is retained only as
> Appendix B (the path not taken, for the INV-8 reviewer).
>
> **Witness decided by operator (2026-07-24): `fna`** — separate power from both dna and rna;
> shared network/switch **explicitly accepted** as a residual (INV-6's named "shared switch").

---

## 0. TL;DR for the reviewer

1. **The tension resolves by recognizing two consensus layers, not one.** ops-hub-A and ops-hub-B
   are **guest VMs**, not corosync members of the `ipnode` Proxmox host cluster (whose members are
   the hosts dna/fna/lna/rna). RCP's consensus group is a **purpose-built arbiter for the ops-hub
   pair, layered *above* `ipnode`** — **`ipnode`'s corosync is NOT modified** (§1).
2. **Chosen mechanism (operator-approved):** a **2-member+witness quorum** (recommended substrate:
   **corosync votequorum + a qnetd QDevice on `fna`, no Pacemaker**) elects exactly one **active
   plane**; the loser **cooperatively stands down**; enforcement rides the **existing
   `ControlPlaneFence`** via a small **active-role precondition** (§3–§4).
   **Proxmox HA is NOT used** — the operator removed it from scope on 2026-07-26 (§6.2). `ipnode`
   keeps zero HA resources, no node becomes self-fence-capable, and VM-level liveness is provided
   by *having a live peer*, not by restarting a dead one. This removes the design's single largest
   blast-radius item and widens exactly two residuals, both named: §2's INV-7 host-death clause and
   §4.5's wedged loser.
3. **INV-7 is met in intent, not literally, and this is documented explicitly (§2).** `wait_for_all`
   is met literally. STONITH (power/BMC) and `priority-fencing-delay` are **not** used — there is
   **no IPMI/BMC driver** (verified in code) and no Pacemaker; the deterministic-winner *intent* is
   preserved by the qnetd tie-breaker + a rank-based election rule, and the loser stands down
   instead of being power-fenced (with an optional Proxmox-API hard-stop for a wedged loser).
4. **Witness: `fna` (confirmed).** Separate power from both dna and rna (removes the storage/power
   correlation that caused the original outage class); **shares the site switch** — an
   **operator-explicitly-accepted residual**, matching INV-6's admitted "shared switch." Not a
   *fully* independent domain — recorded honestly as partial (§2, §7).
5. Everything here is **design-only** and double-gated (P0 rollback-proof gate + INV-8).

---

## 1. The core tension resolved: which "consensus group"?

### 1.1 Two distinct layers, which the plan's language elides

| | **L1 — Proxmox host cluster `ipnode`** | **L2 — RCP control-plane pair** |
|---|---|---|
| Members | dna, fna, lna, rna (**physical PVE hosts**) | ops-hub-A, ops-hub-B (**guest VMs**) |
| Runs corosync? | Yes — on the PVE **hosts** | Not today (they are app guests) |
| Arbitrates | Host quorum, `pmxcfs` writability, Proxmox HA VM placement/restart | *Would* arbitrate: which ops-hub is the **active** control plane |
| Current state | 4 nodes, dna 2 votes, total 5, **quorum 3, no `device{}`** | none — ops-hub-A is the only live plane |

The correction that dissolves the tension: **ops-hub-A is VM 104 *on* dna; it is not dna.** The
ops-hub VMs are **guests** on two of the four hosts; they are **not** corosync members of `ipnode`.
The plan's shorthand ("ops-hub-A (dna)") collapses guest and host, and that collapse is the whole
source of the ambiguity. (If the operator ever intends the ops-hub VMs to be *added as PVE nodes* —
converged/nested Proxmox — that is a different, unusual design and must be stated; nothing indicates
it, and this document assumes they remain guests.)

### 1.2 Why we do NOT add a QDevice to `ipnode`

- `ipnode` is a **healthy 4-node cluster with an odd vote total (5) and quorum 3** — a QDevice is
  the fix for an **even/2-node** cluster with no tiebreaker, and solves no problem `ipnode` has.
- It would **change quorum math for lna and every unrelated homelab workload** — conflating
  "the whole homelab's Proxmox HA" with "this campaign's A/B/witness arbitration," exactly the
  anti-pattern to avoid. (Note: `fna` hosting the RCP *qnetd* below is unrelated to `ipnode`'s
  quorum — qnetd is a separate daemon, not an `ipnode` corosync change; see §7.)
- The clean **2 members + 1 witness** shape (Locked Decision #1) does not map onto a 4-node cluster.

### 1.3 Resolution

> **P1-b's "consensus group" is a purpose-built arbiter for the ops-hub *pair*, realized as a small
> 2-member+witness quorum among the guests (plus a qnetd witness on `fna`), sitting logically
> *above* the Proxmox host cluster. `ipnode`'s corosync is NOT modified.** What we reuse from
> Proxmox is the **corosync/QDevice *technology and pattern***, not the `ipnode` cluster as the A/B
> arbiter, and **Proxmox HA** (a per-VM setting) for VM liveness.

Irreducible residual, named honestly: L2 **nests on L1**. If a PVE host loses quorum and
self-fences (watchdog), the ops-hub guest on it dies regardless of L2's decision — INV-6's
explicitly-accepted residual ("**the PVE corosync quorum itself**"). L2 reduces split-brain of the
*control-plane role*; it cannot escape L1.

---

## 2. INV-7 compliance: met in intent, not literally (explicit, not overstated)

The operator directed that INV-7 be recorded as **met in intent, not literally**, and that this be
documented honestly. Clause by clause:

| INV-7 clause | Literal? | What we actually do |
|---|---|---|
| **`wait_for_all`** | ✅ **Literal** | corosync votequorum `wait_for_all: 1` on the guest quorum — a lone node cannot be quorate at cold start until the pair has formed once. Directly implements "an isolated node is structurally incapable of acting on its peer until quorum re-forms." |
| **STONITH (power/BMC)** | ❌ **Not literal** | **No IPMI/BMC driver exists** (verified — §5). No host power-fence. The loser **cooperatively stands down** on quorum loss (the role gate, §4); a **wedged** loser can be hard-stopped via the **Proxmox-API guest stop** (not a true power-fence — §5). **Host *death* is now handled by nothing** — with Proxmox HA removed (§6.2) no LRM ever holds a lock, so **no node self-fences**. A dead host simply takes its guest with it, which is survivable (the peer becomes active). A host that is **partitioned but alive** is the case that lost its backstop — see §4.5. |
| **asymmetric fencing delay (`priority-fencing-delay`)** | ❌ **Not literal (mechanism)** / ✅ **intent** | No Pacemaker ⇒ no `priority-fencing-delay`. The *intent* — a deterministic, non-symmetric winner — is met by the **rank-based election rule** (active = quorate ∧ lowest-rank member, A-preferred) plus the **qnetd `ffsplit` + `tie_breaker`** deterministic quorum winner (§4, §6). |
| **one deterministic winner, never a symmetric re-provision race** | ✅ **Intent met** | qnetd tie-breaker + election rule ⇒ exactly one active plane in every partition; the loser stands down; neither can unilaterally re-provision the other (no unilateral peer action). Proven by the §8 partition test. |
| **witness in a third *independent* failure domain** | ⚠️ **Partial — operator-accepted** | Witness on **`fna`**: **power-independent** from both members (operator-confirmed), **shares the site switch** (operator-explicitly-accepted residual; matches INV-6's named "shared switch"). Not a *fully* independent domain — recorded honestly as partial (§7). |

**Net:** the *substantive safety properties* (structural no-act-when-isolated; a single deterministic
winner; no mutual re-provision) are preserved. The *literal fencing machinery* (BMC STONITH,
Pacemaker delay) is not used — because it is either unavailable in this environment or heavier than
the operator chose. **Do not read this design as INV-7-literal-compliant.**

---

## 3. The chosen mechanism (lighter, lease-based)

Three cooperating pieces, from bottom to top:

1. ~~**VM liveness → Proxmox HA.**~~ **REMOVED 2026-07-26 (§6.2).** There is no VM-liveness layer.
   A host failure does **not** restart the ops-hub guest, and no node self-fences. Continuity comes
   from the surviving peer becoming active (piece 2), not from resurrecting the dead guest.
   Recovering the lost member is a repair, not an availability event.
2. **Active-plane election → a 2-member+witness quorum.** Recommended substrate below. Produces a
   single, deterministic answer to "which ops-hub is active right now."
3. **Enforcement → the existing `ControlPlaneFence`,** augmented with an **active-role precondition**
   so a standby plane actuates on nothing (§4).

### 3.1 Recommended quorum substrate: corosync votequorum + qnetd QDevice on `fna` (no Pacemaker)

The operator fixed the *shape* (2-member+witness quorum + `ControlPlaneFence`) and the *witness host*
(`fna`), but not the *substrate*. Recommendation and rationale:

- **Members:** ops-hub-A and ops-hub-B each run `corosync` + `corosync-qdevice` over their **stable
  per-node LAN identity** (the plan distinguishes this stable membership identity from the P3 SDWAN
  VIP; corosync is latency-sensitive and must not ride the overlay).
- **Witness:** a **qnetd** daemon on **`fna`** (§7). 2 votes + 1 qdevice vote ⇒ expected 3,
  **quorum 2**; qnetd's `ffsplit` + `tie_breaker` hands the deciding vote to exactly one side.
- **No Pacemaker, no STONITH, no fence agents, no `priority-fencing-delay`.** The app *reads* quorum
  state; it does not drive Pacemaker resources.

**Why this substrate:** (a) most faithful to the plan's "reuse Proxmox corosync+QDevice"; (b) gives
`wait_for_all` **natively** (operator wants it recorded as literally met); (c) deterministic
partition arbitration (qnetd tie-breaker) satisfies "one deterministic winner" without STONITH;
(d) avoids dragging in shared-state/DB questions that belong to later phases. The delta from the
declined literal path (Appendix B) is crisp: **drop Pacemaker + STONITH + `priority-fencing-delay`;
keep corosync votequorum + qnetd + `wait_for_all`.**

**Honest caveat:** this reintroduces **corosync (not Pacemaker)** *inside* the control-plane guests
— a real, though much smaller, failure surface than full Pacemaker+STONITH. It is a deliberate
trade for `wait_for_all` + deterministic arbitration.

### 3.2 Alternative substrate (named, not chosen): a lease store (etcd/Consul, or a Postgres lease)

A TTL lease with a **monotonic fencing token** (Chubby/Kleppmann pattern) would additionally let a
shared resource *reject* a stale leader's writes — a stronger mitigation for the wedged-loser case
(§4.4) than quorum alone. Cost: a new store to run (etcd/Consul) **or** a shared control-plane DB to
lease against (which raises where-does-state-live questions that are **P3-scoped**, not P1-b), and
`wait_for_all` must be emulated in the app rather than obtained natively. **Deferred** as a possible
future hardening; not required for P1-b.

---

## 4. Lease-election + `ControlPlaneFence` integration specifics

### 4.1 What already exists (reuse-first)

`System::Autonomy::ControlPlaneFence`
(`extensions/system/server/app/services/system/autonomy/control_plane_fence.rb`) already fences
every autonomy actuator so a plane acts **only** on instances it owns — its stated purpose is to stop
two planes from "reconcil[ing] the same fleet members … and rac[ing] to reap/reboot them
(double-reap)." Its identity model:
- `control_plane_self_id` = `SiteSetting.get("control_plane_id")` — **this deployment's** id
  (`nil` ⇒ single-plane deployment ⇒ **fence fully inert**, the default).
- per-instance owner = `NodeInstance.config["control_plane_id"]`.
- `owned_by_this_control_plane?(instance)` and `fence_to_control_plane(relation)` are the two guards
  every reconciler already calls.

**Important honesty about scope:** `ControlPlaneFence` today is a *per-instance ownership partition*
(A owns some instances, B owns others), and it **does not stamp owners** ("that is the cutover's job
(#14)"). RCP wants an **active/standby** model (one plane reconciles the *whole* fleet, the other
does nothing). So per-instance ownership alone is **not** the primary protection here — the
active-role gate below is. `ControlPlaneFence`'s ownership check remains as a second layer
(belt-and-suspenders), only biting if/when instances are stamped.

### 4.2 The one new piece: `System::Autonomy::ControlPlaneRole`

A thin, read-only service answering **"is this plane the active one right now?"** from the quorum:

```
active? :=  quorate?  AND  this_node_is_active_by_rule?
```

- `quorate?` — read from corosync votequorum (e.g. via `corosync-quorumtool`/the votequorum API, or
  a small local helper). Encodes `wait_for_all` + the qnetd tie-break for free.
- `this_node_is_active_by_rule?` — the **election rule (§4.3)**.
- **DEFAULT-INERT:** if **no role coordinator is configured** (single-plane / core-mode — the
  default), `active?` returns **true**, so nothing changes for a single-node deployment. The gate
  only bites when a quorum/role coordinator is explicitly configured. This mirrors `ControlPlaneFence`'s
  own careful "inert unless configured" property.

### 4.3 Election rule (this is where INV-7's asymmetry-intent lives)

> **The active plane is the member with the lowest rank *among the current quorate membership*.**

Rank is a stable per-plane priority (A ranked above B). Consequences (all deterministic):

| Situation | Quorate membership | Active |
|---|---|---|
| Both up, healthy | {A, B} | **A** (lowest rank); B stands by |
| Partition, qdevice → A | {A} | **A**; B inquorate ⇒ stands down |
| Partition, qdevice → B (A dead) | {B} | **B** (only quorate member) — correct failover |
| Witness (`fna`) down, A+B still see each other | {A, B} (2 of 3 votes ≥ quorum 2) | **A**; witness loss alone is *not* an outage |
| Witness down **and** A\|B partition | {A} 1 vote, {B} 1 vote — neither quorate | **neither** — both stand down (safe: no split-brain, control plane unavailable until re-form) |

This delivers the deterministic, A-preferred winner that INV-7's `priority-fencing-delay` was
reaching for — at the **election layer**, without any fencing race.

**Failback tunable (flag for the throwaway):** the rule above gives **automatic failback** to A when
A recovers (predictable, A-preferred, but a brief B→A handoff on every A recovery). A "sticky"
variant (incumbent holds until it loses quorum) avoids flapping but drops the strict A-preference.
Evaluate both on the throwaway (§8); default to automatic failback unless flapping proves costly.

### 4.4 The augmentation to `ControlPlaneFence` (proposed; design-only)

Add the active-role precondition to the two existing guards so **every** actuator that already mixes
in `ControlPlaneFence` inherits stand-down with **zero new call sites**:

```ruby
def owned_by_this_control_plane?(instance)
  return false unless control_plane_active?        # NEW: a standby plane actuates on nothing
  self_id = control_plane_self_id
  return true if self_id.nil?
  owner = instance_control_plane_owner(instance)
  owner.blank? || owner == self_id                 # existing per-instance ownership (2nd layer)
end

def fence_to_control_plane(relation)
  return relation.none unless control_plane_active? # NEW: standby reconciles an empty set
  self_id = control_plane_self_id
  return relation if self_id.nil?
  col = "#{::System::NodeInstance.table_name}.config ->> '#{CONTROL_PLANE_ID_KEY}'"
  relation.where("#{col} IS NULL OR #{col} = ?", self_id)  # existing narrowing
end

# NEW. DEFAULT-INERT: true when no role coordinator is configured (single-plane == today).
def control_plane_active?
  System::Autonomy::ControlPlaneRole.active?
end
```

Layered enforcement, honestly labeled:
1. **Primary — the active-role gate** (`control_plane_active?`): only the elected, quorate plane
   actuates. This is the real active/standby protection.
2. **Secondary — per-instance ownership** (existing): unchanged; a backstop that only bites if
   instances are stamped.

### 4.5 Stand-down + the wedged-loser residual

- **Cooperative stand-down (normal case):** on quorum loss the loser's `active?` flips to false and
  every actuator no-ops. This is the expected path and needs no power-fence.
- **Wedged loser (the honest residual):** a loser that is *inquorate but hung* (a stuck process that
  never re-evaluates `active?`) could keep acting. Mitigations, in order:
  1. `active?` is re-checked **at the top of every reconcile/actuate pass** (short, frequent) — a
     healthy-but-inquorate loser demotes within one cycle.
  2. **Optional hard-stop:** the active plane may call the Proxmox-API guest stop on the wedged VM
     (§5) — bounded by the same limitation (works only if the loser's host is reachable+quorate).
  3. **Future hardening:** the lease-store alternative (§3.2) adds fencing tokens so the shared
     substrate rejects a stale leader outright — deferred.
- This residual is precisely what INV-8 and the §8 partition test must probe; it is the price of
  "no STONITH," accepted knowingly.

> **WIDENED 2026-07-26 by the removal of Proxmox HA (§6.2). Read this before the §8 test.**
>
> The worst case is a loser that is **wedged on a host that is partitioned but still running**.
> Every listed mitigation fails there simultaneously, and they fail for *independent* reasons, so
> none of them backstops the others:
>
> - Mitigation 1 assumes the loser's own process still re-evaluates `active?`. "Wedged" is the
>   hypothesis that it does not. It cannot cover its own failure case.
> - Mitigation 2 was **already** useless in exactly this scenario, by §5's own admission — the
>   Proxmox-API guest stop needs the loser's host reachable and quorate, which a partition denies.
> - The watchdog self-fence, previously the only mechanism that worked *because* it needs no
>   reachability, is **gone**. It was the sole non-cooperative option, and it is what the removal
>   actually cost.
>
> **This is not a reason to restore Proxmox HA.** Buying this backstop meant arming dna's watchdog,
> and the firewall's host hard-resetting on a single-ring corosync blip is a far more likely event
> than a wedged-and-partitioned control plane. The correct response is to stop treating stand-down
> as an *action the loser takes* and make it a **structural property**: the actuation path must be
> **fail-closed on quorum**, so that a plane which cannot positively confirm quorum does nothing —
> including a plane that is hung, because a hung plane by definition is not confirming anything.
> Freshness must be *pulled at the actuation point* rather than pushed by a background updater, or
> a wedged updater leaves a stale "I am active" behind and the gate reads it as consent. This is
> INV-1's "structurally incapable of acting" applied to the loser rather than the isolated node.
>
> **Consequences for the §8 test:** the partition test must now include a wedged-loser case, and it
> must fail the design if the loser actuates — a cooperative stand-down passing that test proves
> nothing, because cooperation is the assumption under scrutiny. Simulate wedging by suspending the
> loser's process (SIGSTOP) rather than by stopping it cleanly.

### 4.6 New components P1-b introduces (all gated behind P0 + INV-8)

1. The **corosync votequorum + qnetd (on `fna`)** guest quorum (config in §6) — design-only here.
2. **`System::Autonomy::ControlPlaneRole`** — the thin `active?` reader (quorum + election rule).
3. The **`ControlPlaneFence` augmentation** (§4.4) — proposed code change, not applied.
4. ~~**Proxmox HA** marking of the two ops-hub VMs~~ — **REMOVED 2026-07-26 (§6.2).** P1-b now
   introduces **no change of any kind to `ipnode`**: not its corosync, not its HA manager, not its
   watchdog state. The only thing that lands on an `ipnode` host is the `corosync-qnetd` daemon on
   `fna` (§7), which is a standalone service and not a cluster participant.
5. *(Optional)* a **hard-stop actuator** for a wedged loser, gated behind the same `active?`.

---

## 5. STONITH / fencing reality in this environment — stated plainly

**No host-level power fencing is available today, and the hardware cannot be confirmed from
available information.** This is *why* the design uses cooperative stand-down rather than STONITH.

- **No IPMI/BMC driver in the platform.** `System::InstanceControlService`
  (`extensions/system/server/app/services/system/instance_control_service.rb`, `IMP-bb5fdd6bce28`)
  **explicitly refuses** IPMI power control and Wake-on-LAN — the branches log and return
  `{ success: false, error: "IPMI power control is not implemented" }` rather than fake success.
  Its physical-stop path is **SSH soft-shutdown** (`SshExecutionService`), which needs a reachable,
  cooperative box — **useless as a fence** for a wedged/partitioned node.
- **Whether the hosts even have BMCs/IPMI is unknown** — an operator hardware question (§10).
- **Proxmox host fencing = watchdog self-fence** (softdog by default; hardware/IPMI watchdog only if
  configured), i.e. self-fencing, not peer power-off.
- **The one actuatable fence primitive** is the Proxmox-API guest stop:
  `System::Providers::ProxmoxProvider#stop_instance` →
  `POST /api2/json/nodes/<node>/<kind>/<vmid>/status/{stop|shutdown}`
  (`extensions/system/server/app/services/system/providers/proxmox_provider.rb`). A
  **hypervisor-mediated guest stop**, usable as the optional hard-stop (§4.5) — but it works **only
  when the target VM's host is up, quorate, and API-reachable**, and cannot fence a guest whose host
  is partitioned/dead (rely on the host watchdog there).

---

## 6. Exact config — where and what

> Design-only. **None of this touches `ipnode`.** Values are starting points to validate on the
> throwaway (§8).

### 6.1 corosync votequorum + qnetd — the NEW guest quorum `/etc/corosync/corosync.conf`

```
quorum {
    provider: corosync_votequorum
    wait_for_all: 1                 # cold start: NO partition is quorate until the pair
                                    # has formed once -> a lone node cannot act at boot
                                    # (the mutual-reprovision-at-boot fix; INV-1/INV-2 intent)
    device {
        model: net
        votes: 1
        net {
            tls: on
            host: fna               # qnetd witness — operator-confirmed (§7)
            algorithm: ffsplit      # even-split -> exactly one side keeps the deciding vote
            tie_breaker: lowest      # deterministic winner on a perfect 50/50
        }
    }
}
```

- **Do NOT set `two_node: 1`** — that is for 2 nodes with *no* qdevice; with a qdevice you use the
  `device{}` block (2 + 1 qdevice vote, quorum 2). Setting both is wrong.
- `wait_for_all: 1` is kept **with** the qdevice — it governs the cold-start case; the qdevice
  governs the running-partition case.
- Each member runs `corosync-qdevice`; **`fna` runs `corosync-qnetd`**. TLS on.
- **No `crm`/`pcs`/`stonith` config** — there is no Pacemaker in this design.

### 6.2 Proxmox HA — ~~add the ops-hub VMs as HA resources~~ **REMOVED BY OPERATOR DECISION (2026-07-26)**

> **DO NOT DO THIS.** The ops-hub VMs will **not** be added as Proxmox HA resources. `ipnode` keeps
> **zero** HA resources and every LRM stays `idle, watchdog standby`. Nothing about `ipnode`'s HA
> manager changes. The original text is struck through below for audit.

**Why this was removed.** The original wording — "it does **not** modify `corosync.conf`" — is true
and beside the point. The blast radius is not in the config file it edits, it is in the cluster
state it changes:

- `/etc/pve/ha/resources.cfg` is **empty** today; `ha-manager status` shows all four LRMs
  `idle, watchdog standby` (measured 2026-07-26). **No node on this cluster can self-fence.**
- `watchdog-mux` is nonetheless **active**, `softdog` is loaded, and `/dev/watchdog` is open — the
  machinery is armed and merely lacks an active LRM client.
- Adding the **first** HA resource takes the owning node's LRM active, which connects it to
  `watchdog-mux`. Its host becomes self-fence-capable from that moment.
- ops-hub-A is VM 104 on **dna**. dna also runs **opn-1 (VM 105), the production firewall.**
- `corosync.conf` has a **single ring** (`linknumber: 0`, no redundant link). So one NIC, cable, or
  switch-port event on dna's `10.125.0.10` path would be sufficient to hard-reset the host running
  the firewall — where today the identical event only makes `/etc/pve` read-only while every VM
  keeps running and forwarding packets.

Trading a benign read-only-config failure mode for a hard reset of the firewall's host, in order to
gain automatic restart of a VM whose entire purpose is to have a live peer, is a bad trade.

**What this costs, honestly.** Proxmox HA was providing VM-level liveness: if dna dies, restart
ops-hub-A elsewhere. Without it, a dead dna leaves ops-hub-A down until someone starts it — and note
P0-a's `qmstart` auto-retry cannot help, because it runs *on dna* and dies with the host. Detection
still works (the P0-a watchdog on rna VM 9001 is external and alerts).

That cost is acceptable **because it duplicates, at a lower layer, exactly what this campaign
exists to build.** Continuity after a dna failure is supposed to come from ops-hub-B taking over as
the active plane, not from Proxmox resurrecting ops-hub-A. Restoring A is then a repair at leisure
rather than an availability event. See §2 and §4.5 for the two places this removal genuinely
weakens the design rather than simplifying it.

<details><summary>Original text (superseded)</summary>

> - Add the two ops-hub VMs as HA resources so a host failure restarts them. This uses the existing
>   Proxmox HA/watchdog; it does **not** modify `corosync.conf`. (Exact `ha-manager`
>   group/constraints TBD with P1-a's placement so A stays on dna, B on rna.)

</details>

### 6.3 Application

- `System::Autonomy::ControlPlaneRole` reads §6.1 quorum + applies the §4.3 election rule.
- `ControlPlaneFence` augmentation per §4.4.
- Each plane's `control_plane_id` SiteSetting stays its **stable deployment identity** (A vs B); the
  *active/standby* decision is the role gate, not this id.

---

## 7. Witness placement — `fna` (operator-confirmed)

**Requirement (INV-7):** witness in a third failure domain, not co-located with a member (A on dna,
B on rna).

**Operator decision (2026-07-24): the witness is `fna`** — **power-independent from both dna and rna
(confirmed)**, **on the same network/switch (explicitly accepted residual**, matching INV-6's
admitted "shared switch").

**Assessment, honest:**
- **The meaningful win:** power independence from both members removes the *storage/power*
  correlation that caused the original outage class — dna-data was dna's own ZFS, and a dna
  power/host failure took ops-hub. `fna` shares neither dna's nor rna's power.
- **The accepted residual:** the **shared site switch** remains a genuine correlated domain — a
  switch failure can partition `fna` along with a member. The operator has accepted this knowingly;
  it is INV-6's named "shared switch" that cannot be eliminated on one site. It **must** be recorded
  on the increment, and the §8 test **must** include a witness-side network partition so the
  accepted residual's behavior is demonstrated, not assumed.
- **Mechanically fine:** a qnetd witness **need not be a Proxmox cluster member**, so hosting it on
  `fna` (itself an `ipnode` host) does **not** touch `ipnode`'s quorum — qnetd is a separate daemon.
  `fna` must **not** join the *guest* quorum; it is the qnetd arbiter only.

**Open (minor, non-blocking) checks against `fna` specifically, to close during implementation:**
1. Confirm `fna`'s qnetd reaches **both** ops-hub-A and ops-hub-B over the stable LAN identity with
   low, stable latency (corosync/qdevice is latency-sensitive).
2. `fna`'s own maintenance/reboot cadence: a witness reboot alone is survivable (witness loss ≠
   outage — §4.3), but back-to-back witness+member events are not; coordinate `fna` maintenance
   windows with the ops-hub HA windows.
3. Ensure the qnetd TLS trust between `fna` and the two members is provisioned (design-only note;
   key handling per the crypto-material rules — no key material in configs/logs).

---

## 8. Partition-test acceptance criterion — how it is exercised (sketch only, not executed)

**Never on `ipnode` or the live ops-hub VMs.** Prove the mechanism on a **throwaway lab** first; run
against live A/B only after P0's rollback gate closes **and** INV-8 passes, and then only in a
controlled window.

### 8.1 Throwaway lab

- 3 disposable scratch VMs (local-qemu / the soon-to-be-retired dev box — fine for a throwaway):
  `A'`, `B'` (members, corosync+qdevice) + `W'` (qnetd witness, standing in for `fna`).
- A stub control plane on `A'`/`B'` exposing `ControlPlaneRole.active?` and a logged "actuate"
  action, wired through the augmented `ControlPlaneFence` (§4.4). No real fleet is touched.

### 8.2 Sequence (capture `corosync-quorumtool -s`, the elected `active?`, and the actuate log per step)

1. **Form + baseline.** Quorum present; exactly one of `A'`/`B'` reports `active? == true` (A' by
   rank); the other is standby.
2. **`wait_for_all` proof.** Cold-boot with only `A'` up → it stays **inquorate** and `active?` is
   false until `B'`+qdevice have been seen and the pair has formed once. (Demonstrates the
   mutual-reprovision-at-boot fix — and the honest cold-start caveat in §9.)
3. **Symmetric partition (the dangerous split-brain).** DROP the corosync ring link between `A'` and
   `B'` while both stay up and both still reach `W'`. Assert: qdevice grants quorum to exactly one
   side; that side keeps `active? == true`; the other goes inquorate and **stands down**
   (`active? == false`, actuate log silent). **← core acceptance: one deterministic winner, no
   mutual action.**
4. **Asymmetric / witness-side partitions.**
   - `A'+W'` vs `B'` → **A' active**, `B'` stands down.
   - `B'+W'` vs `A'` (simulate A' dead) → **B' active** (failover; proves it's not "A' always wins").
   - `A'+B'` keep each other, **lose `W'`** → still quorate as a pair (2 of 3), **A' active**
     (witness loss alone ≠ outage — the `fna`-reboot case).
   - `A'|B'` partition **with `W'` also unreachable** → **neither** quorate, **both** stand down
     (conservative: unavailable, not split — **the accepted shared-switch residual from §7**).
5. **Wedged-loser probe.** Force `B'` to keep "acting" after it loses quorum (simulate a hung loser);
   assert the top-of-pass `active?` re-check demotes it within one cycle, and that the optional
   Proxmox-API hard-stop would stop it (stubbed against the disposable VM).
6. **Heal + failback.** Restore the link; assert clean rejoin, no flap storm, and the §4.3 failback
   behavior (A' resumes active) — record whether flapping argues for the sticky variant.

### 8.3 Pass criteria (map to P1-b acceptance)

- **Exactly one** deterministic active plane in every partition; **no mutual action / no
  death-match**; the loser never self-activates.
- `wait_for_all` blocks lone-node action at cold start.
- The witness-loss and switch-failure (witness+member) cases behave as §4.3 predicts (fail
  conservative, no split-brain).
- Winner is the **same** at the quorum layer (qnetd) and the election layer (rank rule).

### 8.4 Evidence bundle for INV-8

Quorum-tool snapshots + `active?`/actuate logs + a per-step timeline + the injected-fault commands,
packaged as the INV-8 artifact (parallels P0-b's rollback-proof evidence). **"Deterministic winner"
must be shown, not asserted.**

---

## 9. Assumptions & uncertainties (explicit — do not treat as settled)

1. **Relied on session-provided ground truth** for `ipnode` (4 nodes; dna 2 votes; total 5; quorum
   3; **no `device{}`**). **Did not read `/etc/pve/corosync.conf`** (it lives on the PVE host, not
   reachable from this guest worktree; design-only anyway). **Re-verify on the host before any
   change** (§10).
2. **Assumed ops-hub-A/B are QEMU guests** (per "VM 104", "VM on rna"), **not** LXC and **not**
   intended to become PVE cluster members.
3. **`wait_for_all` cold-start caveat (real, and desired here):** after a total outage where only one
   member returns, `wait_for_all` keeps it inquorate — it will *not* self-activate until the peer
   returns (or an operator issues a documented manual quorum override). This is the intended
   "no unilateral action at boot" (INV-1/INV-2) but it **has an availability cost**; the manual
   override procedure must be documented as part of implementation, and the §8 test must exercise it.
4. **Corosync ring on the stable LAN identity** is assumed; its latency/reliability is **unmeasured**
   (corosync is sensitive to it) — measure on the `fna` witness path (§7 open check 1).
5. **No IPMI/BMC driver** (verified); **BMC presence on hardware unknown**.
6. **ops-hub-B's role is unconfirmed:** true active/standby control plane vs. warm spare. If B never
   actuates concurrently, the split-brain-of-role risk shrinks further. Confirm with P1-a's owner.
7. **`control_plane_id` is a static SiteSetting** used here as stable deployment identity; the
   active/standby decision is the new role gate, **not** this id. No dynamic rewrite of it is
   required by this design.
8. **The `ControlPlaneFence` augmentation (§4.4) is a proposed code change**, not applied, and must
   preserve the existing default-inert single-plane behavior exactly (verified by keeping
   `control_plane_active?` true when no role coordinator is configured).

---

## 10. What still needs operator / lead input before INV-8 review

> The three biggest forks (mechanism; STONITH-literal-or-not; witness host) are **resolved** —
> lighter/lease-based (§0, §2, §3); INV-7 met-in-intent; **witness = `fna`** (§7). Remaining:

1. **Re-verify `ipnode` on the PVE host** (`pvecm status`, `/etc/pve/corosync.conf`) — confirm still
   4 nodes / dna 2 votes / quorum 3 / no `device{}` before any work.
2. **ops-hub-B's role** — active/standby control plane vs warm spare (affects §4/§9.6 and coordinates
   with P1-a).
3. **Substrate confirmation** — accept the recommended **corosync votequorum + qnetd** substrate
   (§3.1), or elect the lease-store alternative (§3.2) if fencing-token stale-leader rejection is
   wanted now rather than deferred.
4. **Manual quorum-override procedure** (the §9.3 cold-start-survivor case) — operator sign-off that
   a single-survivor cold start requiring manual override is the accepted behavior.
5. **Proxmox-API credential** for the optional hard-stop (§4.5) — a token scoped to power-state on
   only the two ops-hub VMIDs, stored per the crypto-material rules.

**Sequencing gate:** none of this executes until **P0's rollback-proof gate (P0-b) closes** and the
**INV-8** pass on this design completes — same gating as P1-a's actual provisioning.

---

## Appendix A — Load-bearing source references

- `System::Autonomy::ControlPlaneFence` —
  `extensions/system/server/app/services/system/autonomy/control_plane_fence.rb` (the existing
  actuator fence this design augments; default-inert; per-instance ownership; static
  `control_plane_id` SiteSetting).
- No-IPMI finding —
  `extensions/system/server/app/services/system/instance_control_service.rb` (`IMP-bb5fdd6bce28`;
  `execute_physical_start`/`execute_physical_stop` refuse IPMI/WoL; physical stop is SSH
  soft-shutdown only).
- Proxmox guest-stop primitive (the optional hard-stop) —
  `extensions/system/server/app/services/system/providers/proxmox_provider.rb#stop_instance`
  (`POST /api2/json/nodes/<node>/<kind>/<vmid>/status/{stop|shutdown}`) and `.../proxmox/client.rb`.
- Invariants INV-6 / INV-7 and Locked Decisions —
  `~/.claude/plans/campaign-reciprocal-control-plane.md`.

## Appendix B — Declined alternative: literal-INV-7 (guest Pacemaker + STONITH + `priority-fencing-delay`)

Retained for the INV-8 reviewer as the path not taken (operator declined it in favor of the lighter
lease-based option, §0).

- A standalone **corosync + Pacemaker** cluster inside the two ops-hub guests + qnetd QDevice.
- `stonith-enabled=true`; `property priority-fencing-delay=15s`; asymmetric `pcmk_delay_base` on two
  fence resources (each stops the *other* ops-hub VM via a `fence_pve`-style agent calling the
  Proxmox API); node priority makes A the fence-race winner.
- **Why declined:** heaviest option; runs Pacemaker *inside* the very control plane it protects; the
  fence agent needs Proxmox credentials (a stop-VMs token is a real blast-radius object); and the
  STONITH it promises is **not** true host power-fencing anyway in this environment (no BMC driver —
  §5), so the literal machinery buys little over cooperative stand-down while adding a large failure
  surface. The lighter option preserves the substantive properties (§2) at a fraction of the risk.

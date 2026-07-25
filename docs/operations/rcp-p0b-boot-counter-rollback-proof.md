# RCP v2 · P0-b — Boot-Counter Rollback Proof (design)

> **STATUS: DRAFT design deliverable — NOT executed, NOT landed.**
> **INV-8 Fable adversarial review: COMPLETE — verdict needs-rework (procedure-level,
> not structural); all four required changes are incorporated in this revision**
> (injection containment, watchdog decomposition, arm-only scoping, five precision
> edits). **Remaining gates before any live run: explicit human sign-off + a
> human-observed first run (INV-10 first-of-class).** No live test was triggered to
> produce or revise this document.
>
> Campaign: Resilient Control Plane (RCP) v2 · `019f9250-a199-7819-ace6-cee904116b3e`
> Increment: `p0b-boot-counter-rollback-proof` · Model: Opus (design), Fable (review)
> Full campaign design: `~/.claude/plans/campaign-reciprocal-control-plane.md`

## 1. Verdict (TL;DR)

The A/B boot-counter **machinery already exists** — campaign `019f505f`
("Smooth Boot-Image Upgrades") increment 3 built systemd-boot A/B slots +
boot-counting, landed on `develop` via submodule bump `90899eeca`. **P0-b is
not a build-from-scratch; it is the hardware-validation that `019f505f` inc 3
explicitly deferred**, PLUS two invariant gaps that must be closed for the proof
to be *genuine* rather than theater:

| Invariant | Machinery present? | Genuinely satisfied today? |
|---|---|---|
| **INV-2** boot never depends on network | Yes — local systemd-boot picks a local UKI; update pull is post-boot | **Yes** (needs proving under a severed link) |
| **INV-3** rollback lives below the payload | Partial — the *slot selection/fallback* is in systemd-boot (below the kernel), but the *reboot trigger* for a kernel-up/agent-dead node is **absent from the image** | **No, not unattended** — see §4.2 |
| **INV-4** "good" is EARNED via health checks + a bake window | **No** — the slot is blessed on the agent's **first heartbeat** (base-os liveness), with no app-health gate and no bake window | **No** — see §4.1 |

Net: the rollback *reverts correctly once a reboot happens*, but nothing in the
current image (a) prevents a boots-but-broken slot from being frozen as good, or
(b) autonomously triggers the revert reboot when the kernel comes up but the
payload is dead. Both are net-new and are the substance of P0-b.

## 2. What `019f505f` already provides (do not rebuild)

Landed, on `develop` (code lives in the `extensions/system` submodule):

- **A/B slots + systemd-boot boot-counting** — `agent/internal/bootslots/bootslots.go`.
  Two UKI entries under `/EFI/Linux`: `powernode-a.efi` / `powernode-b.efi`.
  Counter filenames `powernode-<slot>+<tries>.efi`. Active slot tracked in
  `/persist/var/lib/powernode/boot-slot.json` (survives reboot; only advances on
  a *confirmed* healthy slot).
- **Image ships slot A as the pinned good default** — build script
  `initramfs/images/disk-image-amd64-uefi/build-disk-image-amd64-uefi.sh`
  writes `loader.conf` (`timeout 3`, `default powernode-a*`, `editor no`), slot A
  as counterless `powernode-a.efi`, systemd-boot at `/EFI/BOOT/BOOTX64.EFI` +
  `/EFI/systemd/systemd-bootx64.efi`.
- **In-place upgrade orchestration** — `agent/internal/bootupgrade/bootupgrade.go`
  `Apply()`: download → sha256 recheck → **cosign verify (never skipped)** →
  write INACTIVE slot boot-counted (`BootTries = 3`) → `bootctl set-oneshot`
  the new slot. Default stays A (rollback target). It does **not** reboot.
- **Bless / rollback bookkeeping** — `bootupgrade.ConfirmBoot()` +
  `agent/internal/espwrite/espwrite.go` (`WriteUKISlot`, `BlessSlot`,
  `CleanSlot`, `SlotGoodExists`). Bless = strip the counter (`+N-M` → `.efi`),
  confirm the good file exists, then `bootctl set-default`. Rollback = clean the
  failed slot's counter files, leave the active slot unchanged.
- **Operator trigger + delivery + accounting** — `system_upgrade_boot_image` MCP
  action (`server/app/services/ai/tools/system_fleet_tool.rb`), agent-delegated
  dispatch (`execution_dispatcher.rb` `AGENT_DELEGATED_COMMANDS`), post-reboot
  success accounting via `BootImage::UpgradeReconciler` (booted `git_sha` ==
  target, else fail after `TIMEOUT_SECONDS`, default 900). Loop-bounded by a
  `/persist` attempt marker + `SystemTaskReaperJob`.
- **Booted-image identity** — `agent/internal/identity/bootimage.go`
  `BootedImageGitSHA()` reads `powernode.image_git_sha=` from `/proc/cmdline`
  (baked per-UKI at build). This is how "booted new" vs "rolled back to old" is
  distinguished. **The injected broken slot MUST carry a distinct `git_sha`.**
- **Fable already cleared the brick path (design-level, inc 3):** "every failure
  direction ends at a bootable older image." What was **deferred**: the
  "systemd-boot boot flow ... cannot be booted in CI — it MUST be validated on
  real UEFI/OVMF hardware before an A/B image is promoted to the fleet," and a
  dedicated A/B ops doc. **P0-b is that deferred hardware validation.**

The **selection/fallback is genuinely below the payload**: systemd-boot
(`systemd-bootx64.efi`, an EFI binary that runs before the kernel) decrements the
`+N` counter on each attempt and, on a consumed one-shot or exhausted counter,
selects the still-good default (A). No OS, no agent, no network involved in the
selection.

**Critical asymmetry — only the FORWARD path was hardware-validated.** `019f505f`
inc 5 (`inc5-inplace-upgrade-validated`) proved the **success** direction on real
OVMF: ops-hub `019f54fd` upgraded `b0e0fc7→34f2af6` in-place, blessed, promoted,
`/persist` cert preserved, no re-provision. The **rollback direction — a
deliberately-bad slot auto-reverting — was never exercised on hardware.** That is
precisely P0-b's charter. (Two `019f505f` artifacts to carry forward: offline
nodes verify with `cosign --insecure-ignore-tlog` because they can't reach
Sigstore TUF/Rekor — matters for the INV-2 network-severed run; and inc 5 hit a
real "wrong cosign public key" bug where the platform key didn't match the CI
signing key — reinforcing the §5.1 test-key discipline: verify the throwaway's
public key actually pairs with the test signer before the run.)

Also note: the campaign shows **7 of 8** tasks passed, but the one non-terminal
task (`increment-ops-hub-bootstrap-re-provision-...`, `pending`) is a **superseded
duplicate** of the re-provision that `inc5-hub-bootstrap` actually completed — **no
delivered capability is missing** because of it.

## 3. Gaps that make the proof genuine (net-new)

### 3.1 INV-4 gap — bless is apply-time-ish, not health-earned

`agent/internal/runtime/service.go` (~L266-285) blesses on the **FIRST successful
heartbeat**:

```
// boot-image A/B bless (campaign 019f505f inc 3): the FIRST successful
// heartbeat means this boot is healthy, so we bless the running systemd-boot
// entry (disarming auto-rollback) ...
bootBlessed := false
... PostSend: func() { if !bootBlessed { ConfirmBoot(...); bootBlessed = true } }
```

`ConfirmBoot` blesses when `bootedGitSHA == PendingSHA` — an **identity** match
("did the target image boot?"), **not a health** check. The heartbeat is emitted
by the base-os agent regardless of whether the *composed* control plane is
serving. So a slot that boots base-os, heartbeats once, and is otherwise broken
(composed hub-backend 500s, a module failed to compose, it crashes at t+2min) is
**frozen as good** — exactly the `#39` failure INV-4 exists to prevent.

**Reuse-first fix already exists in the codebase for the *sibling* problem.**
`agent/internal/runtime/lkg_capture.go` (the frozen module-LKG capturer) gates on
precisely the right signal and says why, verbatim:

> "Why app-level (composed `/up` 200), not the agent heartbeat: the agent lives
> in base-os and heartbeats regardless of whether the composed hub-backend is
> healthy. A hub-backend that boots-but-500s would falsely 'confirm' on agent
> liveness."

It requires **`RequiredConsecutive` healthy `/up` probes (default 3) over a poll
interval** ("a short window that avoids capturing on a single flapping 200") and
promotes the **breadcrumb** (what THIS boot cold-composed and is now serving),
never the live hot-reconciled state. The module-LKG got the `#39` treatment; the
**boot-slot bless did not.** The fix is to gate the bless on the **same
app-health + consecutive-probe bake window** LKGCapturer already implements —
ideally sharing the `HealthProber` + `resolveGate` machinery so there is one
health definition, not two.

### 3.2 INV-3 gap — no below-payload reboot *trigger* for the kernel-up case

`systemd-bless-boot.service` is **masked** in this image (documented in
`espwrite.go` L95: "done HERE by the agent (health-gated) rather than
systemd-bless-boot.service (masked)"), and a grep across `extensions/system`
(`modules/`, `initramfs/`, `agent/`) finds **no** `RuntimeWatchdogSec`,
`WatchdogSec`, `nmi_watchdog`, `panic=`, `/dev/watchdog`, or greenboot health-
reboot unit. The kernel cmdline is
`console=tty0 console=ttyS0,115200 powernode.boot=1 ip=dhcp` (+ baked
`powernode.image_git_sha=`) — **no `panic=`**.

Consequence: the revert needs a **second boot** (reboot #1 = the one-shot attempt
of the bad slot; reboot #2 = back to A). Nothing in the image triggers reboot #2:

- **Kernel/UKI dead-on-arrival** (panic before/at switch_root): with no `panic=1`
  the box may **hang** instead of resetting; the revert then waits on the
  hypervisor/firmware or an operator. Not unattended by default.
- **Base-os up, payload dead** (agent may even heartbeat): the box **sits on the
  bad slot indefinitely** — default is still A, but no reboot occurs, so the
  revert never fires on its own.

So the below-payload *selection* is real, but a genuine **"survive a dead/
unresponsive agent" unattended revert (INV-3)** needs a reboot trigger that does
**not** depend on the agent or the composed payload. It decomposes into **three
distinct failure modes**, each with its own correct mechanism (an earlier draft's
"a health service pets the watchdog only while healthy" is **mechanically wrong**:
`RuntimeWatchdogSec` is petted by PID1 *unconditionally* while systemd is alive,
and PID1 owns `/dev/watchdog` *exclusively* — a separate health unit cannot share
it):

- **(i) base-os up, payload dead** (systemd/PID1 alive; the common case, incl. a
  dead agent). **No watchdog needed** — systemd is alive by definition. A
  standalone **bake-deadline unit** (a systemd `.timer`/oneshot independent of the
  agent process, so it survives a dead agent) checks `boot-slot.json`: if
  `Pending != ""` and the slot is **not blessed within deadline T**, it runs
  `systemctl reboot`, escalating to `reboot -f` if that stalls. Reboot #2 →
  default A. This is the agent-independent trigger for the dead-payload/dead-agent
  case.
- **(ii) kernel / PID1 hang** (systemd itself wedged, can't run the unit above).
  `RuntimeWatchdogSec` in systemd — but this **requires an actual watchdog
  device**. **Open item:** confirm whether the throwaway VM (and fleet VMs
  generally) expose one — Proxmox `i6300esb` on the VM, or the `softdog` kernel
  module; it likely must be **added to the VM spec**, not assumed. Without a
  device `RuntimeWatchdogSec` is inert and this case falls through to (iii)/P0-a.
- **(iii) DOA** (kernel never reaches PID1): `panic=N` on the UKI cmdline resets on
  a **panic** — but not on a **hang** (see §5.1 Variant A). A hang here is covered
  only by the external probe below.

**External watchdog = P0-a** ("Minimal fix + monitoring") is an out-of-band probe
that detects a dead/unreachable node and can `qm reset` it — the legitimate
backstop for the residual (ii)-without-device and (iii)-hang cases. P0-b should
**not silently depend** on it for its core acceptance; ship (i) + `panic=N`,
resolve (ii)'s device question, and treat P0-a as the backstop.

An agent-initiated "reboot myself after the bake window fails" is a fine **fast
path** but is **not sufficient alone** — INV-3's whole point is that a bricked/
hung agent can't run its own undo, so mode (i)'s trigger is a *separate* systemd
unit and modes (ii)/(iii) live entirely below the OS.

## 4. Throwaway test target

**Finding: no existing live, idle, disposable UEFI VM is a safe target. A fresh,
dedicated throwaway must be provisioned — and the exact host/storage/VMID is an
operator decision (flagged, not decided here).**

Evidence from the live fleet (374 nodes / 329 instances):

- The fleet is dominated by **ephemeral CI builder pool** nodes
  (`ci-builders-amd64-pool-*` ×64, `ci-native-builders-amd64-pool-*` ×277) — not
  UEFI A/B control-plane images, actively leased by the native-build pipeline;
  hijacking one desyncs CI. Not safe, not applicable.
- The named test nodes that *sound* disposable are all **historical — every
  instance TERMINATED**: `inc14-reboot-survival` (3 instances, all terminated),
  `inc20-claude-tmux-rehearsal-node` (terminated), `dev-cell-accept-*`
  (terminated). No live VM to reuse.
- `ops-hub` (node `019f4ebc…`) is **explicitly off-limits** — it is the
  production control plane RCP exists to protect, and its instance rows are
  `error`/stale (it self-repointed to standalone VM104 on `dna`).
- `k3s-a-*`, `tenant-a/b-host` are running workloads; `physical-smoke-pve` is
  physical (can't cheaply A/B a borrowed box). None disposable.

Therefore the target is a **purpose-provisioned, single-use VM**:

- **Fresh OVMF/UEFI QEMU VM** (systemd-boot A/B requires UEFI — `bootslots.
  BootedViaSystemdBoot()` keys off the `LoaderInfo` EFI variable, which needs an
  OVMF efidisk). Provision from the **dev plane** (`/opt/powernode`), which can
  drive Proxmox via `ProxmoxProvider` (the path used to recover ops-hub).
- **Imaged with a post-inc-3 capability image** (A/B `/EFI/Linux` layout,
  systemd-boot, `/usr/bin/cosign`) — e.g. the same `34f2af6d`-class image ops-hub
  was validated on, or a fresh CI build.
- **Genuinely disposable**: brand-new VMID, its own disk; brick/rollback affects
  nothing else. Destroy on completion.

**Operator decisions to confirm before any provisioning (do not decide these
unilaterally):**

1. **Host + storage.** Recommendation: **`rna` / `local-data`** (rna's
   independent zpool) — keeps the throwaway entirely **off `dna`**, where ops-hub
   (VM104) lives, honoring INV-6 failure-domain separation. Residual, honestly
   named: even a separate-VMID/separate-disk throwaway shares `rna`'s CPU/RAM/IO
   and PVE corosync membership; `rna` is also the intended P1 home for ops-hub-B.
   If the operator would rather not run a deliberately-panicking VM on `rna` at
   all, the alternative is a scratch host outside the quorum. **Operator picks.**
2. **VMID.** Must avoid the shared-PVE VMID-collision hazard
   (`[[shared-dna-vmid-collision-ops-hub-dev]]` — the shared pool has no VMID
   floor and previously grabbed a live VMID). Pin an explicit, reserved,
   non-colliding VMID.
3. **Injection containment** — the broken artifact is injected via the **mandatory
   local-CLI-staged path**, never platform dispatch (SAFETY-CRITICAL; see §5.1).

## 5. Concrete design

### 5.1 Injection method — a validly-signed, deliberately-broken UKI

**Hard constraint:** cosign verify is **never skipped** (`bootupgrade.Apply`
step 2; the whole point of INV-5). You therefore **cannot** inject by corrupting
UKI bytes — that is refused before the ESP write and only tests the supply chain,
not the rollback. A broken *slot* must be a **legitimately cosign-signed but
functionally-broken image** with a **distinct `git_sha`**.

**Containment (corrected per INV-8 review — SAFETY-CRITICAL).** An earlier draft
claimed a test-key signature makes the broken UKI "structurally unable to be
accepted by any real node." **That is false.** Cosign keys are **not**
per-node-pinned: `upgrade_dispatcher.rb` reads a **platform-global** env var
(`POWERNODE_COSIGN_PUBLIC_KEY[_FILE]`) and ships the key **inside the dispatch
envelope**; the agent verifies against whatever key rides in the task. So a
test-key-signed broken UKI dispatched through the **normal platform path is NOT
contained** — a mis-targeted dispatch (exactly the VMID-collision operator-error
class flagged in §4) could deliver a *verifying-but-broken* UKI to a **real fleet
node**, which unpatched code would then bless on its first heartbeat. **The
platform-dispatch path for the broken artifact is therefore FORBIDDEN.**

**Mandatory containment = the local-CLI-staged path (no platform involvement).**
Inject entirely on the throwaway, so the test key never touches platform env and
the broken artifact never enters the publication catalog:

1. Pre-stage the broken UKI on the throwaway at
   `/persist/cache/boot-image/<sha256>.uki` — `bootupgrade.Apply` **skips the
   download** when the staged file's sha matches (`bootupgrade.go:98`), so no
   platform pull happens.
2. Stage the test cosign **public** key + bundle as local files on the throwaway.
3. Run `powernode-agent upgrade-boot-image --cosign-public-key-file <pub>
   --cosign-bundle-file <bundle> --reboot` (flags exist, `commands.go:1131-1138`).
   This drives the **same** `Apply → sha256 → cosign-verify → WriteUKISlot →
   set-oneshot` path, so write fidelity is identical to production — only the
   *trigger* and *key source* are local.

**Explicitly forbidden anywhere in this procedure:** touching dev's
`POWERNODE_COSIGN_PUBLIC_KEY[_FILE]`, promoting/registering the broken UKI as a
`DiskImagePublication`, or dispatching it via `system_upgrade_boot_image`. The
test keypair is generated and held in **CI/Vault** (never CLI-generated, never
output); this design **never handles or emits private key material** — only the
public half + bundle are staged, as files, on the throwaway.

**Two failure flavors (build both; run B as primary, A as the hard-case):**

- **Variant B — boots base-os, payload never healthy (PRIMARY, deterministic).**
  Build a UKI (real CI `build-disk-image.yaml` amd64-UEFI job, test-key-signed,
  new `git_sha`) whose base-os + agent come up but whose **composed control plane
  never serves `/up` 200** — e.g. compose points at a non-existent/broken module
  version, or a base-os-only image with no composed hub-backend. This is the most
  controlled failure (no reliance on panic behaviour) and it **directly exercises
  INV-4**: identity matches (target booted) but health never passes → must NOT
  bless → must revert. **Under today's unpatched code this slot is WRONGLY
  blessed on the first heartbeat** — running B against unpatched code first is the
  honest demonstration that the INV-4 gap is real; then apply §3.1 and re-run to
  show correct rollback. **The unpatched demo run must keep the network UP
  throughout** — that bless rides a real heartbeat POST, so severing the link would
  suppress the very (wrong) bless it means to expose. Only the patched **revert**
  run severs the network (§5.3).
- **Variant A — kernel/UKI dead-on-arrival (SECONDARY, hardest clause).** Must
  provably **panic**, not hang: an "unmountable root" typically **hangs in initrd**
  (a `dracut` emergency shell / retry loop), and `panic=N` does **not** fire on a
  hang. Pick a breakage that panics deterministically — a **truncated/corrupt
  initramfs** section, or `init=/nonexistent` (kernel panics "No init found") — and
  **smoke it in local QEMU first** to confirm it panics (not hangs) before the
  throwaway run. Revert trigger is `panic=N` (§3.2 mode iii). **Residual, named:** a
  hang-style DOA is *not* covered by `panic=N`; it falls to the external P0-a probe
  / a VM watchdog (§3.2 mode ii) — do not claim Variant A proves the hang case.

**Fidelity note:** the mandatory local-CLI path above is not a lower-fidelity
shortcut — it invokes the **same** `bootupgrade.Apply` (same sha256 recheck, same
never-skipped cosign verify, same `WriteUKISlot` + `bootctl set-oneshot`) the
platform-dispatched production path invokes. Only the *dispatch trigger* (a local
command vs. a `System::Task`) and the *key/artifact source* (local files vs. the
platform envelope + OCI pull) differ — and those differences are exactly what
keeps the broken artifact off every real node.

### 5.2 Health-gate criteria (exact)

Bless a slot **only** when ALL hold (reusing `lkg_capture.go` machinery):

1. **Identity:** `BootedImageGitSHA()` == `boot-slot.json` `PendingSHA` (the
   target actually booted). *(present today)*
2. **App-level health, not agent liveness:** the **composed control plane**
   answers `/up` **2xx** (loopback self-probe, node mTLS identity), per
   `HTTPHealthProber`. *(net-new for the bless path; reused from LKGCapturer)*
3. **Bake window:** **`RequiredConsecutive` healthy probes (default 3)** over the
   configured poll interval, with **no failure** breaking the streak — i.e.
   "structural across the entire pre-freeze window," matching LKGCapturer's
   `Run()`. Only then invoke `ConfirmBoot` to bless (strip counter +
   `set-default`). *(net-new for the bless path)*

Make `RequiredConsecutive` + interval **operator-tunable** (breadcrumb /
SiteSetting), never hardcoded (`[[no-hardcoded-budgets-configurable]]`). Target a
bake window in the **~60–90 s** band to stay within the campaign's sub-90 s
measured-rollback ethos while still catching an early crash.

If (1) holds but (2)/(3) never do within the failure budget → **do not bless**;
default stays A; the §3.2 mode-(i) bake-deadline unit forces reboot #2 → revert.

**Arm-only scoping (required before this ships beyond the throwaway).** The
bless-gate **and** the §3.2 mode-(i) bake-deadline reset **arm only while
`boot-slot.json` `Pending != ""`** (an upgrade is genuinely in flight) and
**disarm on bless or on revert-detection** (`booted != Pending`). Without this, a
node with no composed `/up` — the **CI-builder majority**, and any base-os-only
class — would fail the health gate on every ordinary boot and **reboot-loop**, and
non-hub upgrades would become **permanently unblessable** (one-shot consumed →
auto-revert, forever, every time). Arming only during an in-flight upgrade confines
the whole mechanism to the exact window it is for.

**Per-node-class health resolution (required for generality).** The probe URL is
resolved from the boot breadcrumb's `AppHealth.URL` (`LKGCapturer.resolveGate`).
The **throwaway is hub-class** (a composed control plane with `/up`), so the gate
is well-defined and the proof is valid **for that class**. For classes with **no
composed app** (`AppHealth.URL` empty) the "healthy" definition is undefined — a
fallback (agent-liveness, or a node-class-appropriate check) **must be specified
before** the gate is enabled fleet-wide. Until then, scope this bless-gate to
composed-control-plane nodes; do **not** treat it as applicable to the whole fleet.

### 5.3 Expected timing & behaviour

**Two distinct runs — do not conflate their network posture:**

**Run 1 — unpatched INV-4 demo (network UP throughout).** Variant B against current
code: base-os + agent boot, first heartbeat POSTs, `ConfirmBoot` sees
`booted == Pending` and **wrongly blesses** the broken slot (identity-only gate).
This must run **online** — the wrong bless rides a real heartbeat; severing the link
would hide the very failure it demonstrates. Expected (and damning) result: the
broken slot becomes the permanent default. This is the "before."

**Run 2 — patched revert run (network SEVERED to prove INV-2).** Variant B against
§3.1-patched code:

| t | Event | Layer |
|---|---|---|
| t0 | Local CLI on the throwaway: `powernode-agent upgrade-boot-image --cosign-public-key-file … --cosign-bundle-file … --reboot` (broken UKI pre-staged at `/persist/cache/boot-image/<sha>.uki`) | agent (local) |
| t0+s | Agent: sha256 (staged) → **cosign verify (test key, file)** → `WriteUKISlot powernode-b+3.efi` → `bootctl set-oneshot` → persist `Pending=b/PendingSHA` → attempt marker → `systemctl reboot` | agent |
| **t0+s′** | **SEVER the throwaway's network** (prove the revert needs no net) | test harness |
| +≤3 s | Reboot #1: systemd-boot honours the one-shot → boots `powernode-b` (rename `+2-1`); **clears `LoaderEntryOneShot` before kernel exec** (fail-safe — a crash before bless cannot re-select the bad slot) | **below kernel** |
| boot | base-os + agent up; composed `/up` **never 2xx** (broken by design) | payload dead |
| bake | Health gate: never 3 consecutive 2xx → **never blessed**; default stays A | agent gate |
| +T | §3.2 **mode-(i) bake-deadline unit** (`Pending != ""`, unblessed within T) → `systemctl reboot` (→ `reboot -f` if it stalls) — independent of the agent | **below payload** |
| +≤3 s | Reboot #2: no one-shot → systemd-boot selects `default powernode-a` (good) → boots A | **below kernel** |
| back | Node is running the pinned good slot A | — |

**Acceptance for Run 2 (observed locally, network still severed): booted A **and**
`bootctl` default still `powernode-a` **and** slot B **unblessed** (still
counter-suffixed / not promoted).** Do **not** use "Pending cleared" as the
criterion — `ConfirmBoot`'s `CleanSlot(b)` + Pending-clear runs on a PostSend
*after a heartbeat*, which needs the network; that bookkeeping is expected only
once the link is **restored** (a clean follow-up assertion, not part of the
severed-run acceptance). Measure t0→booted-on-A. Run 1 then supplies the "before"
that makes the before/after honest.

### 5.4 Invariant satisfaction

- **INV-2 (boot ≠ network):** already true by construction (local UKI, local
  systemd-boot; update pull is post-boot). **Proven** by severing the link at
  t0+s′ (Run 2) and observing the revert complete offline.
- **INV-3 (rollback below the payload):** slot selection/fallback is in
  systemd-boot (below the kernel) — present. Made **unattended and
  agent-independent** by the §3.2 trigger set: mode-(i) standalone bake-deadline
  unit (dead payload/agent, systemd alive), mode-(ii) `RuntimeWatchdogSec` + a VM
  watchdog device (PID1 hang — **device presence is an open item**), mode-(iii)
  `panic=N` (DOA panic). The "dead agent" clause is proven by killing the
  agent/payload and still reverting via mode (i).
- **INV-4 (good is EARNED):** bless is moved from "first heartbeat" to
  **app-health `/up` 2xx × 3 consecutive over a bake window** (§5.2), reusing the
  LKGCapturer definition, **armed only while an upgrade is in flight**. A
  boots-but-broken slot can no longer be frozen good **within the bake window**;
  LKG is earned by a *completed* health-gated bake, never captured at apply-time.
  **Residual, named honestly:** this protects only up to the bless. A slot that
  passes the bake window and is blessed, then fails **later**, has **no
  below-payload undo** — it is now the good default; recovery is a fresh upgrade
  cycle or external/out-of-band action. A longer bake window trades rollout speed
  for a smaller post-bless exposure but cannot eliminate it.

## 6. Net-new work required for P0-b (scoped)

1. **Gate the boot-slot bless on app-health + bake window** (§3.1/§5.2) — refactor
   `service.go`'s first-heartbeat bless to drive `ConfirmBoot` from the
   LKGCapturer-style `HealthProber`/consecutive-probe gate (share, don't
   duplicate, the health definition). *Agent, Go.*
2. **Below-payload revert trigger set** (§3.2) — (i) a standalone systemd
   bake-deadline unit (reboot when `Pending != ""` and unblessed within T,
   agent-independent); (ii) `RuntimeWatchdogSec` **plus confirming/adding a VM
   watchdog device** (i6300esb/softdog) for the PID1-hang case; (iii) `panic=N` on
   the UKI cmdline. *base-os module + image build + VM spec.* **Not** "a health
   service pets the watchdog" — mechanically impossible (PID1 owns `/dev/watchdog`).
3. **Deliberately-broken UKIs (Variant A + B)** signed by a **test cosign keypair
   in CI/Vault**, injected **only** via the mandatory **local-CLI-staged path** on
   the throwaway (§5.1) — never via platform dispatch, never touching dev's global
   `POWERNODE_COSIGN_PUBLIC_KEY`, never entering the publication catalog. *CI +
   operator; no key material handled/emitted by the implementer.*
4. **Throwaway provisioning recipe** (§4) — fresh OVMF VM, reserved VMID, on the
   operator-chosen host/storage; teardown step.
5. **The A/B ops doc `019f505f` inc 3 deferred** — fold this design's validated
   procedure into `extensions/system/docs/` once proven (closes that debt).

## 7. Do-not-execute gate (INV-8 / INV-10)

This is boot-critical, root-of-trust-adjacent, and rollback-machinery. Per the
campaign's discipline: **(a)** independent **Fable** adversarial review of THIS
design — **DONE** (claim refuted: cosign keys are not per-node-pinned; verdict
needs-rework; the four required changes are folded into §3.2 / §5.1 / §5.2 / §5.3 /
§5.4 / §6, per the status banner); **(b)** explicit **human sign-off** — *pending*;
**(c)** the first live run is **human-observed once** (INV-10 first-of-class) —
*pending*. Only then does anyone watch it execute for real. No live
failure-injection was performed for this document or its revision, and none should
be until (b)–(c) clear.

## 8. As-provisioned state (2026-07-24, VMID 9002 on rna)

The P0-b throwaway is provisioned and staged up to (but NOT including) the injection:

- **VM:** `rcp-p0b-throwaway-9002` (VMID 9002) on **rna**, disk on **local-data**
  (zpool `local-zfs/local-data`, independent per INV-6). OVMF/q35, secure boot OFF
  (`pre-enrolled-keys=0`), serial-only console `/var/run/qemu-server/9002.serial0`.
  Running; boots **slot A** of capability image git_sha `a60b0a0d…`; enrollment
  pending (no identity injected — expected). Config matched to the fleet's
  `create_uefi_disk_vm_instance` / `build_qemu_vm_body`. Only 9002 was created;
  rna's 9001 (another agent's watchdog) + 7 stopped VMs untouched.
- **Source-image provenance:** the cached `.raw` sha differs from the OCI
  publication sha by a *systematic* ~316-byte PVE-import transform (confirmed
  across 3 images) — it is the fleet's real imported capability image.
- **Staged in `/persist/cache/boot-image/`** (offline write to the persist
  partition ONLY — ESP left untouched, no slot written, no set-oneshot):
  - `0ae697d0fa662ef82210f03c7d014a4977c585e57bda457e24f924f8fef74f47.uki` — the
    **Variant-A DOA broken UKI** (real 6.8.0-136 kernel + **empty initrd** +
    cmdline `panic=1 console=ttyS0,115200 powernode.image_git_sha=deadbeef…`).
    QEMU-smoke-confirmed: kernel panics (`VFS: Unable to mount root fs`) then
    `Rebooting in 1 seconds` (panic=1). **Unsigned** — signing deferred (§9.2).
  - `rcp-p0b-test-signing.pub` — the test cosign public key (Vault transit key
    `rcp-p0b-test-signing`, non-exportable).
- **Access finding:** neither offline `/persist` key injection (sshd fetches keys
  live from the platform post-enrollment into the read-only initramfs rootfs — not
  a persist path) nor MCP-driven enrollment (no claim-confirm / claimable-physical
  MCP tool exists) can establish shell access autonomously. Access is an **operator
  step** (§9.1) — which fits, since the run is human-observed anyway.

## 9. Human-observed run procedure (gated on INV-8/INV-10 sign-off — do NOT run without it)

1. **Establish shell access (operator).** Minimal-template enrollment: pre-create a
   claimable physical NodeInstance on a minimal-template Node (e.g. `ci-builder-amd64`,
   4 modules, platform `019e7c7e`) with `ssh_key` = the deploy pubkey; then confirm
   the VM's broadcast claim code in the operator UI, OR write a real `identity.cfg`
   (`ID=<that instance UUID>`, `SERVER=https://dev.ipnode.us`) to the VM's ESP and
   reboot (claim-by-ID auto-confirm). Post-enroll the agent fetches the deploy
   pubkey → `ssh root@<vm-ip>`. Confirm `/usr/bin/cosign` present.
2. **Sign the broken UKI (operator mints a FRESH Vault token first — old one expired).**
   With the `rcp-p0b-test-signing` policy token in env, on any host with cosign + the
   UKI file:
   `cosign sign-blob --key hashivault://rcp-p0b-test-signing --tlog-upload=false --bundle 0ae697d0….uki.cosign-bundle <path>/0ae697d0….uki`
   (`--tlog-upload=false` keeps the bundle offline; the node verifies with
   `--insecure-ignore-tlog` per the inc5 fix). Stage the `.cosign-bundle` onto the VM
   at `/persist/cache/boot-image/0ae697d0….uki.cosign-bundle`.
3. **Run the injection (THE observed step).** SSH to the VM, then:
   ```
   powernode-agent upgrade-boot-image \
     --uki-sha256 0ae697d0fa662ef82210f03c7d014a4977c585e57bda457e24f924f8fef74f47 \
     --target-git-sha deadbeefdeadbeefdeadbeefdeadbeefdeadbeef \
     --cosign-public-key-file /persist/cache/boot-image/rcp-p0b-test-signing.pub \
     --cosign-bundle-file /persist/cache/boot-image/0ae697d0….uki.cosign-bundle \
     --reboot
   ```
   Apply skips the download (sha-named UKI pre-staged), cosign-verifies against the
   test pubkey, writes slot B `powernode-b+3.efi`, `bootctl set-oneshot`, reboots.
4. **(Optional, proves INV-2)** sever the VM's network right after the reboot is
   initiated.
5. **Observe the rollback** on the serial socket: reboot #1 → slot B → kernel panic
   (empty initrd / no root) → `panic=1` reboot → one-shot consumed → systemd-boot
   selects default **slot A** → VM back on the good image. Agent-independent +
   network-independent revert (INV-3 / INV-2).
6. **Acceptance:** booted A **and** `bootctl` default still `powernode-a` **and**
   slot B unblessed. (Variant-A kernel-DOA proof of INV-3; the INV-4
   health-gate/bake-window proof — §5.3 Run 2 — needs the §3.1/§3.2 patched image,
   deferred.)
7. **Teardown:** `qm stop 9002 && qm set 9002 --protection 0 && qm destroy 9002` on
   rna; remove the claimable NodeInstance record.

**Scope:** this round is **Variant A only** (kernel-DOA, runnable on the current
unpatched image). It does NOT exercise INV-4's health-gated bless / bake-window —
that requires the net-new §3.1/§3.2 code built into a fresh capability image.

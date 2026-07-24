# RCP v2 · P0-b — Boot-Counter Rollback Proof (design)

> **STATUS: DRAFT design deliverable — NOT executed, NOT landed.**
> Gated behind an independent Fable adversarial review (INV-8) **and** explicit
> human sign-off before any live failure-injection runs (INV-10 first-of-class,
> human-observed once). This document is the artifact those gates review. No live
> test was triggered to produce it.
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
unresponsive agent" unattended revert (INV-3)** additionally requires a reboot
trigger that does **not** depend on the agent or the composed payload. That
trigger is net-new. Options, best-first:

1. **OS-level health-watchdog in base-os (recommended, below the payload).** A
   `powernode-boot-health.service` (+ `RuntimeWatchdogSec` / hardware `/dev/watchdog`)
   that pets the watchdog **only while the app-health gate (§3.1) is passing**.
   A hung agent OR a dead composed app stops the pets → the watchdog resets the
   box → reboot #2 → systemd-boot selects A. This is genuinely agent-independent
   and network-free.
2. **`panic=1` (or `panic=10`) in the UKI cmdline** for the DOA case, so an early
   kernel panic auto-resets instead of hanging. Cheap, complements (1).
3. **External watchdog = P0-a.** RCP P0-a ("Minimal fix + monitoring") is exactly
   an external probe that detects a dead/unreachable node and can `qm reset` it.
   This is a legitimate below-the-node trigger and the intended backstop, but it
   is a *separate* increment; P0-b should not silently depend on it for its core
   acceptance. Treat P0-a as the backstop, ship (1)+(2) for a self-contained
   proof.

An agent-initiated "reboot myself after the bake window fails" is a fine **fast
path** but is **not sufficient alone** — INV-3's whole point is that a bricked/
hung agent can't run its own undo, so the trigger must also exist below it.

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
3. **Trust isolation for the broken artifact** — see §5.1.

## 5. Concrete design

### 5.1 Injection method — a validly-signed, deliberately-broken UKI

**Hard constraint:** cosign verify is **never skipped** (`bootupgrade.Apply`
step 2; the whole point of INV-5). You therefore **cannot** inject by corrupting
UKI bytes — that is refused before the ESP write and only tests the supply chain,
not the rollback. A broken *slot* must be a **legitimately cosign-signed but
functionally-broken image** with a **distinct `git_sha`**.

**Trust isolation (recommended, and it satisfies crypto-material-safety).** Sign
the broken UKI with a **dedicated test cosign key** whose **public** half is
provisioned onto the throwaway's platform only (`POWERNODE_COSIGN_PUBLIC_KEY[_FILE]`),
never onto any production platform. Then a deliberately-broken image is
**structurally unable** to be accepted by any real fleet node (different key), so
it can never be mis-promoted. The keypair is generated and held in **CI/Vault**
(never on a CLI, never output); this design **never handles or emits private key
material**.

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
  show correct rollback.
- **Variant A — kernel/UKI dead-on-arrival (SECONDARY, hardest clause).** A
  test-key-signed UKI that panics early (broken initramfs / unmountable root).
  Exercises INV-3's "even if the kernel doesn't come up" clause; revert trigger is
  `panic=1` (§3.2 opt 2) or the hypervisor's reboot-on-panic — purely
  firmware/hypervisor, fully below the payload.

**Delivery of the injection:** the normal `system_upgrade_boot_image` MCP action
targeting the throwaway instance (writes the inactive slot + `set-oneshot` +
reboots). For a tighter loop that skips platform-side publication plumbing, the
manual `agent upgrade-boot-image --reboot` CLI subcommand drives the same
`bootupgrade.Apply` (still cosign-verifies; still needs the signed artifact).
Either way the write path is unchanged from production — that fidelity is the
point.

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
default stays A; the §3.2 trigger forces reboot #2 → revert.

### 5.3 Expected timing & behaviour (primary run, Variant B, patched)

| t | Event | Layer |
|---|---|---|
| t0 | Operator triggers `system_upgrade_boot_image` (broken, test-signed UKI) | platform |
| t0+s | Agent: pull → sha256 → **cosign verify (test key)** → `WriteUKISlot` `powernode-b+3.efi` → `bootctl set-oneshot` → persist `Pending=b/PendingSHA` → attempt marker → `systemctl reboot` | agent |
| **t0+s′** | **SEVER the throwaway's network** (prove INV-2: revert must need no net) | test harness |
| +3 s | Reboot #1: systemd-boot honours one-shot → boots `powernode-b` (rename `+2-1`), clears one-shot | **below kernel** |
| boot | base-os + agent up; composed `/up` **never 2xx** (broken by design) | payload dead |
| bake | Health gate: never 3 consecutive 2xx → **never blessed**; default stays A | agent gate |
| +bake | **Health-watchdog stops petting** → watchdog reset (or agent fast-path reboot; DOA→`panic=1`) | **below payload** |
| +3 s | Reboot #2: no one-shot → systemd-boot selects `default powernode-a` (good) → boots A | **below kernel** |
| back | Healthy boot on A; `ConfirmBoot` sees booted≠Pending → `CleanSlot(b)`, clears Pending | agent |

**Acceptance (matches P0-b + INV):** the throwaway returns to the pinned good
slot A **unattended, with the network severed, and without the agent/payload
participating in the revert**. Measure t0→recovered-on-A. Then the same run
against **unpatched** code demonstrates the INV-4 gap (Variant B is wrongly
blessed) — the before/after that makes the proof honest.

### 5.4 Invariant satisfaction

- **INV-2 (boot ≠ network):** already true by construction (local UKI, local
  systemd-boot; update pull is post-boot). **Proven** by severing the link at
  t0+s′ and observing the revert complete offline.
- **INV-3 (rollback below the payload):** slot selection/fallback is in
  systemd-boot (below the kernel) — present. Made **unattended and
  agent-independent** by the §3.2 OS-level watchdog + `panic=1` trigger. The
  "dead agent" clause is proven by killing the agent/payload and still reverting.
- **INV-4 (good is EARNED):** bless is moved from "first heartbeat" to
  **app-health `/up` 2xx × 3 consecutive over a bake window** (§5.2), reusing the
  LKGCapturer definition. A boots-but-broken slot can no longer be frozen good;
  LKG is earned by a *completed* health-gated bake, never captured at apply-time.

## 6. Net-new work required for P0-b (scoped)

1. **Gate the boot-slot bless on app-health + bake window** (§3.1/§5.2) — refactor
   `service.go`'s first-heartbeat bless to drive `ConfirmBoot` from the
   LKGCapturer-style `HealthProber`/consecutive-probe gate (share, don't
   duplicate, the health definition). *Agent, Go.*
2. **Below-payload revert trigger** (§3.2) — `powernode-boot-health.service` +
   `RuntimeWatchdogSec`/`/dev/watchdog` petted only while `/up` is healthy; add
   `panic=1` to the UKI cmdline for the DOA case. *base-os module + image build.*
3. **Deliberately-broken, test-key-signed UKIs** (Variant A + B) + **test cosign
   keypair in CI/Vault** + throwaway-only public-key provisioning (§5.1). *CI +
   operator; no key material handled/emitted by the implementer.*
4. **Throwaway provisioning recipe** (§4) — fresh OVMF VM, reserved VMID, on the
   operator-chosen host/storage; teardown step.
5. **The A/B ops doc `019f505f` inc 3 deferred** — fold this design's validated
   procedure into `extensions/system/docs/` once proven (closes that debt).

## 7. Do-not-execute gate (INV-8 / INV-10)

This is boot-critical, root-of-trust-adjacent, and rollback-machinery. Per the
campaign's discipline: **(a)** independent **Fable** adversarial review of THIS
design first (give it the specific claim to refute: "the §5 procedure genuinely
reverts a bad slot unattended, network-free, with a dead agent, and cannot freeze
a bad slot as good"); **(b)** explicit **human sign-off**; **(c)** the first live
run is **human-observed once** (INV-10 first-of-class). Only then does anyone
watch it execute for real. No live failure-injection was performed for this
document, and none should be until (a)–(c) clear.

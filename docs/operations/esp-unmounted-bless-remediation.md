# Remediation: unblessed boot slots on composed fleet nodes ("ESP unmounted")

**Date**: 2026-07-30 · **Status**: recommendation, no changes made
**Scope**: ops-cell (VM 9003, wedged), ops-hub (VM 600, not wedged), dev-cell (VM 9000, unreachable)
**Author**: remediation review (Fable), from source in `/opt/powernode/extensions/system`

---

## 0. Executive verdict

**The unmounted ESP is not the defect. It is the design.** The bless path mounts the ESP
on demand and unmounts it after every write. What is actually blocking the bless on
ops-cell is the **health gate in front of it**: `BootConfirmer` refuses to touch the ESP
until the node's "own composed app" answers healthy N consecutive times, and the
compile-time default health URL is `https://127.0.0.1/up` — loopback Traefik → hub-backend
Rails — which only exists on a **self-hosting** node. On ops-cell nothing listens there,
the probe gets `connection refused` forever, the gate never passes, and the bless code —
which is present and correct in the running binary — is simply never reached.

The `lkg_capture:probe: Get "https://127.0.0.1/up": connection refused` line looping every
15s in ops-cell's journal, set aside in discovery as "a separate concern," **is the bless
blocker made visible**: both gates are built from the same `healthURL` variable
(`agent/internal/runtime/service.go:411-441`) and share one prober
(`lkg_capture.go:146-166`). The LKG capturer logs its probe failures; `BootConfirmer`
does not (`bootconfirm.go:84-96` resets the counter silently) — hence "zero confirm/bless
lines" while the same failing probe was being logged under another goroutine's name.

Do **not** mount `/boot/efi` in fstab, on any node. It fixes nothing and regresses a
deliberate safety property (§1).

---

## 1. Q1 — Is the unmounted ESP the defect, or intended? **Intended.**

Evidence, all from files read:

- `agent/internal/espwrite/espwrite.go:1-5` (package doc): "It locates the ESP, mounts it
  if needed, and writes /EFI/Linux/<slot> entries atomically".
- `espwrite.go:273-307` — `withMountedESPReal`: "locates + mounts the ESP (fresh rw when
  it isn't already mounted — **post-switch_root the ESP is unmounted, so this is the
  write path**), runs fn, syncs, and unmounts what it mounted." It mounts to a fresh
  `MkdirTemp("", "powernode-esp-")` (`espwrite.go:333-346`), **never** `/boot/efi`.
- `espwrite.go:101-107` — `BlessSlot` doc: blessing is "done HERE by the agent
  (health-gated) rather than systemd-bless-boot.service (masked), which can't run anyway
  (**the ESP isn't mounted rw at /boot post-pivot** and the binary isn't on PATH)."
- The agent source contains **zero** references to `/boot/efi` (grepped; none outside
  test paths). An empty `/boot/efi` is cosmetic.

Every ESP operation — `WriteUKISlot`, `BlessSlot`, `CleanSlot`, `SlotGoodExists`,
`SetLoaderDefault` — goes through `withMountedESP` (`espwrite.go:79-181`). ConfirmBoot's
design assumption is therefore *correct*: it does not need a mounted ESP. The layer that
owns ESP mounting is the agent, on demand, and it already does.

Why unmounted-at-rest is the right design and must not be "fixed": the ESP is vfat — no
journal — and it is the only boot medium. A permanently rw-mounted FAT filesystem on a
node that can lose power dirty is how you corrupt the one partition with no redundancy.
Mount-for-seconds, sync, unmount bounds that exposure to the writes themselves
(`espwrite.go:288-306` syncs twice: after fn and before unmount). The fleet has already
had one ESP-integrity incident (ops-hub's 1021MiB-filesystem-on-512MiB-partition); do not
widen the write window.

## 2. The actual defect (three parts)

**2a. The default health gate presumes self-hosting.**
`service.go:66`: `const defaultAppHealthURL = "https://127.0.0.1/up"`, documented as
"loopback Traefik (:443) → hub-backend Rails /up … Verified on VM104" — i.e. validated on
the self-hosted hub and silently wrong for every other node class. The override chain that
was designed to retune this centrally exists but is empty end-to-end:
`SiteSetting "system.boot_lkg.app_health_url"` (server:
`extensions/system/server/app/controllers/api/v1/system/node_api/modules_controller.rb:72-74`)
→ envelope (`agent/internal/runtime/modules_client.go:82-84,105`) → boot breadcrumb
(`lkg.go:116`, written **pre-pivot** at compose, `compose.go:170-175`) →
`BootConfirmer.resolveGate` (`bootconfirm.go:129-141`). Discovery confirmed no
`system.boot_lkg.*` SiteSetting is set, so every non-self-hosting node falls to the
compile-time loopback default and can never pass the gate. Note the setting is
**platform-global** — there is no per-node/per-template override — so it cannot express
"hubs probe /up, cells probe something else."

**2b. The gate blocks even the *rollback verdict*, not just the bless.**
`bootconfirm.go:84-109`: `ConfirmBoot` is only invoked after `required` consecutive
healthy probes. But `ConfirmBoot`'s fallback branch (`bootupgrade.go:489-496`, "provably
running the OTHER slot: sd-boot fell back … clear the attempt") needs no health at all —
it is evidence-based (EFI variables only). On a gate-blocked node, `Pending` can therefore
**never** clear, even after a genuine rollback; the comment at `bootupgrade.go:236-241`
("both outcomes clear Pending, so this unblocks by itself") is false for this node class.
This is why rebooting ops-cell would *not* un-wedge it (§3, option C).

**2c. The gate fails silently.** `bootconfirm.go:87-96`: a probe error just resets the
counter; `OnError` fires only for `ConfirmBoot`'s own errors (`bootconfirm.go:99-103`).
A node can sit unblessed for the life of a boot with no journal line from the
`boot_confirm` goroutine. Compounding it server-side: `UpgradeReconciler` marks the
upgrade task **complete** on booted-sha match alone
(`extensions/system/server/app/services/system/boot_image/upgrade_reconciler.rb:44-46`) —
the platform declares victory at "booted", not "blessed", so a node primed to silently
revert looks green everywhere.

**The ops-hub asymmetry, explained.** ops-hub self-hosts the platform, so
`https://127.0.0.1/up` genuinely answers 200 there (the comment at `service.go:61-66` was
validated on it, as VM104). Its gate passes, `ConfirmBoot` runs, `BlessSlot` mounts the
ESP on demand, blesses, unmounts. `active="b", no pending` is exactly that path having
completed. No ESP-was-mounted-earlier history is needed; the unmounted ESP never was an
obstacle. This also predicts the fleet pattern: **only self-hosting nodes can bless;
every cell-class node that takes a boot-image upgrade will wedge exactly like ops-cell.**
dev-cell, if it ever took one, is presumptively in the same state (unverified — §6).

## 3. Q2 — Un-wedging ops-cell

State (verified in discovery): `active="a"`, `pending="b"`, `last_target_sha=312e6048`,
running 312e6048 from slot b, healthy for 5h+ by human observation, one-shot consumed,
sd-boot default still slot a. Slot b's ESP file carries a boot counter (after one
successful selection it will be `powernode-b+2-1.efi` — systemd-boot decrements at
selection). Consequence of doing nothing: **any reboot silently reverts to the old slot-a
image**, and all upgrades stay refused.

Options:

- **A. Fix the gate config for this boot, let it bless organically.** The breadcrumb for
  the *current* boot was written pre-pivot without an `app_health` override; a SiteSetting
  change reaches the breadcrumb only at the next compose (= next boot, which is itself a
  revert — circular). The only no-reboot vector is editing
  `/persist/var/lib/powernode/boot-composed.json` to add
  `"app_health":{"url":"<truthful-local-url>"}` and restarting the agent (`resolveGate`
  re-reads the breadcrumb at start, `bootconfirm.go:131`). **Blocked in practice:** it
  requires a loopback HTTP endpoint on ops-cell that returns 200, and I cannot confirm one
  exists (I could not inspect ops-cell's composition; uncertainty stated). If one exists
  this is the most honest option — it exercises the real INV-4 path. Failure mode: none
  destructive; if the URL is wrong the node just stays wedged.

- **B. Manual bless + state fix (RECOMMENDED).** Mirror exactly what
  `ConfirmBoot` would have done (`bootupgrade.go:513-544`), which has precedent (ops-hub
  was blessed by hand 2026-07-28, `bootslots.go:53-56`). Commands, on ops-cell as root:

  ```
  esp=$(blkid -L BOOT)                          # locateESP order, espwrite.go:311-327
  mount -t vfat -o rw "$esp" /boot/efi          # the empty mountpoint that already exists
  ls /boot/efi/EFI/Linux/                       # EXPECT powernode-a.efi + powernode-b+*.efi; STOP if not
  mv /boot/efi/EFI/Linux/powernode-b+2-1.efi /boot/efi/EFI/Linux/powernode-b.efi
                                                # use the exact name ls showed
  bootctl set-default powernode-b.efi           # EFI var; same call the agent makes (bootupgrade.go:527)
  sed -i 's/^default .*/default powernode-b.efi/' /boot/efi/loader/loader.conf
                                                # mirror SetLoaderDefault (espwrite.go:167-231); skip if no file
  sync; umount /boot/efi
  systemctl stop powernode-agent
  printf '{"active":"b"}' > /persist/var/lib/powernode/boot-slot.json
  python3 -c 'import json;print(json.load(open("/persist/var/lib/powernode/boot-slot.json")))'  # parse-verify
  systemctl start powernode-agent
  bootctl status | grep -A2 'Default'           # verify default = powernode-b.efi
  powernode-agent abandon-boot-image            # dry-run; MUST print "no boot-image upgrade pending"
  ```

  The state write must clear `pending`, `pending_sha` AND `last_target_sha` — leaving
  `last_target_sha` would re-arm the reconcile path (`bootupgrade.go:318-330`) which is
  still health-gated and would keep `ConfirmNeeded` true forever. `{"active":"b"}` is
  byte-identical to what `State.Save` would produce (omitempty, `bootslots.go:41-64`).

  Failure modes, honestly stated: a botched rename leaves slot b with no boot file → next
  reboot falls back to blessed slot a (old image; recoverable, not a brick). A garbled
  state file → `Load` defaults to `{active:"a"}` (`bootslots.go:252-263`) while the node
  runs b — **this is the dangerous one**: with `Pending` empty, a later upgrade would pass
  the guards and overwrite slot b, the running image (`bootupgrade.go:246-259` only checks
  slot *a*'s file exists). Hence the parse-verify step and the dry-run check are not
  optional. **Brick analysis**: nothing in this procedure touches slot a or
  `/EFI/BOOT/*` (systemd-boot itself); both slots remain present and bootable throughout;
  the true-brick precondition (overwriting the bootloader, the removed single-slot path,
  `espwrite.go:61-70`) cannot be reached. Worst realistic outcome of getting it wrong is
  a reboot onto the old slot-a image.

- **C. Reboot and "let the counter roll back".** Rejected. The reboot lands on slot a
  (default; one-shot consumed), but the fallback *verdict* is also behind the health gate
  (§2b), so `Pending` survives and upgrades stay refused — you lose 312e6048 and keep the
  wedge. Strictly worse than doing nothing.

- **D. `powernode-agent abandon-boot-image --yes` now.** Rejected — its own dry-run text
  warns for exactly this state (`commands.go:1685-1690`): the node is *running* the
  pending slot, and abandon deletes that slot's counter files, i.e. the image it booted
  from. Guaranteed revert at next reboot. That tool is for wrong-target-sha attempts, not
  this.

- **E. Leave it.** Rejected: a canary that cannot take upgrades is not a canary, and any
  unplanned reboot is a silent revert.

**Decision: B now; A2's spirit returns as the durable fix (§5). Do not dispatch the
40b4a69b upgrade until the durable gate fix is on the node** — with the gate still broken
it would bless-wedge again with roles swapped (running unblessed slot a).

## 4. Q3 — Ordering

**Rule 0: no reboots of any node whose slot state is (or may be) pending, and no
boot-image dispatches fleet-wide, until each node's bless state is resolved.** A reboot of
a pending node is a silent revert (§3C).

1. **ops-cell** — manual bless + state fix (§3B). ~15 min, zero blast radius, and it
   produces a verified runbook for dev-cell if needed. Ops-cell is then safe to reboot
   again.
2. **dev-cell** — diagnose then recover per §6. Second because it is dark (unknown slot
   state ⇒ Rule 0 applies to it) and its /persist carries the ship-updates capability;
   but nothing about it should be rushed while it is "running" per qm.
3. **ops-hub** — **no state action needed or wanted.** It is blessed, not pending
   (verified in discovery), and its health gate is truthful on that node. It takes the
   durable fix **last**, after canary soak (§5). Resist the urge to "harmonize" ops-hub
   while it is the only self-observing control plane you have.
4. **Fleet rollout** of the durable fix + sensor: ops-cell (canary, including one full
   organic bless drill) → dev-cell → ops-hub.

## 5. Q4 — The durable fix, and where it ships

Four changes; the first three are agent code, the fourth spans agent + extension server.

1. **Decouple the evidence-based verdict from the health gate** (fixes §2b).
   `BootConfirmer.Run` should, before entering the health-probe loop, evaluate the
   *rollback* verdict once: if `Pending` is set and `BootedSlot()` provably names the
   OTHER slot (`bootupgrade.go:489-496`), clear the attempt immediately — no health
   required, because no bless happens on that branch. Blessing (both the Pending path and
   `reconcileUnblessedBootedSlot`) stays strictly health-gated; INV-4 is untouched.

2. **An honest default gate for non-self-hosting nodes** (fixes §2a). When the breadcrumb
   carries no `app_health.url`, replace the unconditional loopback-/up default with a
   node-truthful one: systemd health — no failed units / `is-system-running` not
   `degraded` — for N consecutive polls. That is precisely "did *this node's* composed
   stack come up" for a node whose composed stack is systemd units, and it exists on every
   node class. Self-hosted planes then get the strong gate *explicitly*: set SiteSetting
   `system.boot_lkg.app_health_url = https://127.0.0.1/up` on the hub plane (the delivery
   chain already exists end-to-end, §2a, and this matches the config-not-hardcoded
   convention). Optional later: per-template override server-side; not required to close
   this incident.

3. **Make the gate audible** (fixes §2c). In `BootConfirmer`, when a slot is pending and
   the gate has not passed for longer than a threshold (say 10 min), emit one
   `OnError("boot_confirm_gate", …)` line naming the URL and last probe error, then
   repeat hourly. Three lines of code; would have turned tonight's 5-hour silence into a
   journal line at minute ten.

4. **Detection** — see §7.

**Vehicles** (the platform ships three separate modules; agent ≠ extension ≠ content):

- Changes 1-3 are **agent code** → ship in the **`powernode-system-base` module**, which
  is what actually delivers `/usr/sbin/powernode-agent`
  (`extensions/system/modules/powernode-system-base/manifest.yaml:5,16-24` — "ships the
  cross-compiled Go agent binary"). **Not** a disk-image/UKI rebuild: the module overlay
  shadows the UKI's baked agent and wins (verified fleet behavior; confirm delivery with
  `sha256sum /usr/sbin/powernode-agent`, never via `image_git_sha`). **Not** hub-backend.
  Publish → recompose → **reboot** per node (live module refresh does not remount the
  composed union; boot-time only).
- Change 4's server half is **extension server code** → the `powernode-extension-system`
  module; its agent half (heartbeat field) rides the same system-base rebuild as 1-3.
- Process: this is boot-critical pre-pivot-adjacent code — apply the recorded two
  independent critics practice before landing, and land the failing test first
  (`reconcile_bless_test.go` / `bootconfirm_test.go` already model the seams;
  `SetESPMountForTest`, `SetStatePathForTest`).

## 6. Q5 — dev-cell (VM 9000) recovery without SSH or console

The observed triad — host key regenerated despite /persist-backed host keys, operator key
rejected, agent presumably certless/silent — is most consistent with **dev-cell having
booted without (or with an empty view of) its /persist**: host keys, authorized_keys
material, and the agent's mTLS cert all live there. A slot rollback alone would not
change host keys (modules and /persist are slot-independent), so suspect the persist
mount, not (only) the image. The missing serial socket despite `serial0: socket` in
config is unexplained — a QEMU process started against a different/older config would do
it, but after a dna reboot autostart should have applied current config. Treat as
unverified; first diagnostic below resolves it. Sequence, least- to most-invasive:

1. **From dna, read-only**: `qm config 9000 --current`, `qm pending 9000`,
   `ls /var/run/qemu-server/ | grep 9000` (does `.qmp` exist where `.serial0` doesn't?),
   `qm monitor 9000` → `info status`, `info chardev`. This costs nothing and settles
   whether the running QEMU matches its config.
2. **QGA, if configured**: `qm agent 9000 ping`; if it answers, *small* guest-execs only
   (<500 bytes — oversized guest-exec permanently jams qemu-ga's parser; and note the
   known reply-path breakage class): `mountpoint /persist`, `cat` of
   `/persist/var/lib/powernode/boot-slot.json`.
3. **Offline inspection** (the reliable path): `qm stop 9000` (stop+start, never reset),
   then **set a lock** before touching storage (`qm set 9000 --lock backup`) — a
   reconciler/watchdog restarting the VM mid-surgery while the host has the volume
   mounted is the documented dual-mount truncation hazard. Mount the VM's disk zvol on
   dna **read-only first** and read: `/persist/var/lib/powernode/boot-slot.json` (is
   dev-cell also pending?), ssh host keys + authorized_keys, the boot breadcrumb, PKI
   dir; and the ESP partition (which `powernode-*.efi` files exist, `loader/loader.conf`).
   **No safety snapshot is possible right now** — dna's z_zvol taskq is wedged and any
   zvol snapshot hangs in D-state — so keep writes minimal, and verify every write after
   unmount (documented failure class: writes to a still-dual-mounted blob hash clean on
   the host and read as zeros in the guest).
4. **Repair offline as evidence dictates**: restore authorized_keys/host-key material on
   /persist; if slot state is pending, do the §3B bless *offline* (rename + loader.conf +
   boot-slot.json). Limitation: `bootctl set-default` writes an EFI **variable** and
   cannot be run offline; if the efidisk varstore's default points at the old slot, the
   first boot comes up on it anyway (old image, blessed — safe), and you run
   `set-default` from inside once SSH is back. Do not hand-edit the varstore.
5. Clear the lock, `qm start 9000`, and use the now-recreated serial socket (step 1 will
   have confirmed it appears on a fresh QEMU process) if SSH is still down.
6. **Re-provision is near-last-resort**: it destroys /persist — dev-cell's build
   checkout + Go toolchain (the proven ship-updates capability) and its enrollment PKI
   (whose on-disk cert is the only thing short-circuiting re-enrollment). Only if the
   disk itself proves corrupt.

Stranding risks to avoid: writing /persist while the VM runs (truncation); leaving the
qm lock set afterward; `qm reset` (qemu-level changes need stop+start); any zfs snapshot
attempt on dna (hangs unkillable until the taskq wedge is cleared).

## 7. Q6 — Detection: never again 5 silent hours

The platform already has the exact pattern to copy. `BootedImageGitSHA` rides the
heartbeat (`agent/internal/runtime/heartbeat.go:42-48`), is ingested by
`status_controller.rb:69` into `NodeInstance#record_heartbeat!`, and is consumed by
`BootImageDriftSensor` (`…/fleet/sensors/boot_image_drift_sensor.rb:20-56`, one deduped
signal per instance). Mirror it end to end:

- **Agent**: add `boot_slot_active` / `boot_slot_pending` / `boot_slot_pending_sha` to
  `HeartbeatPayload` from `bootslots.Load()` — a /persist file read, no ESP access, no
  lock contention (read-only `Load`, not `Update`).
- **Server**: persist on `NodeInstance` via `record_heartbeat!`; new
  `UnblessedBootSlotSensor` emitting `system.boot_slot_unblessed` (severity high) when
  `boot_slot_pending` is present and instance uptime exceeds ~30 min
  (`UptimeSeconds` already rides the payload, `heartbeat.go:101`), fingerprint
  `unblessed_slot:<instance_id>`, observation-bound first like boot-image drift
  increment 1. This also gives `UpgradeReconciler` the field it needs to someday gate
  task completion on *blessed*, not merely *booted* (§2c) — worth a TODO, not this
  increment.
- **Interim, zero-build, today**: extend the existing external watchdog on dna with a
  per-node SSH check — `boot-slot.json` contains `"pending"` and its mtime is older than
  30 min → alert. One cron line per node; retire it when the sensor lands.

## 8. What must NOT be done — consolidated

1. **No fstab / persistent `/boot/efi` mount** on any node — regresses a deliberate
   integrity property, fixes nothing (§1).
2. **No reboot of any pending-slot node** before its bless state is resolved — silent
   revert (§3C), and the gate bug means even the rollback verdict won't clear.
3. **No `abandon-boot-image --yes` on a node running its pending slot** (§3D).
4. **No boot-image dispatches anywhere** until the gate fix ships — each one manufactures
   another wedged node.
5. **No global `system.boot_lkg.app_health_url` pointing away from `/up`** — it is
   platform-global and would weaken ops-hub's truthful gate to fix the cells' broken one.
6. **No ops-hub changes in this incident's first wave** — it is healthy, blessed, and the
   only self-observing control plane; it goes last.
7. **No re-provision of dev-cell** except on proof of disk corruption — /persist is the
   asset (§6). No zfs snapshots on dna until the z_zvol wedge clears.
8. **No landing of the agent changes without the two-critics review** and a
   re-introduced-bug test proving each guard is reachable — the ConfirmBoot caller-gate
   near-miss is the standing lesson that a fix below a short-circuit is dead code.

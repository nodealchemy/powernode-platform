# RCP v2 · P0-b — the rollback proof FAILED, and why that was the point

**Date:** 2026-07-25 · **Campaign:** `019f9250-a199-7819-ace6-cee904116b3e` ·
**Increment:** `p0b-boot-counter-rollback-proof` (recorded **failed**) ·
**Observation:** `019f9a73-ee6c-759c-a841-f8e8dd656fc3`

Companion to [`rcp-p0b-boot-counter-rollback-proof.md`](./rcp-p0b-boot-counter-rollback-proof.md)
(the design). That document specified the test; this one records what the test found.

## TL;DR

The A/B boot-counter rollback that INV-3 depends on **has never worked, on any node, ever.**
A one-line wrong GUID made the "did we boot via systemd-boot?" check return `false`
universally, so every boot-image upgrade silently took a legacy path that **overwrites
systemd-boot itself with the new payload**. A payload that fails to boot therefore has
nothing left to roll back to.

The test was supposed to prove rollback works. It proved the opposite, on a throwaway,
one increment before the same machinery was scheduled to be pointed at the live control
plane.

## What happened

Injected the staged, validly-cosign-signed but deliberately-broken UKI on throwaway
**VM 9002** (rna/local-data) at 17:57 UTC via the local-CLI path (§9 of the design; the
platform-dispatch path stayed forbidden throughout).

The agent reported `boot image written + cosign-verified` and rebooted. Then:

| Observed | Count |
|---|---|
| Boots of the broken image (`git_sha=deadbeef…`) | **48** |
| Kernel panics (`VFS: Unable to mount root fs`) | **24** |
| Boots of the good slot (`git_sha=a60b0a0d…`) | **0** |
| Automatic recoveries | **0** |

An unbounded panic-reboot loop. It did not self-recover; the VM was stopped by hand.

## Root cause

Offline forensics on the stopped VM's ESP (mounted read-only from the Proxmox host):

```
/EFI/BOOT/BOOTX64.EFI       sha256 0ae697d0…f74f47   ← the broken UKI
/EFI/BOOT/BOOTX64.EFI.bak   sha256 46f2f18c…         ← byte-identical to
/EFI/systemd/systemd-bootx64.efi  sha256 46f2f18c…      systemd-boot
/EFI/Linux/powernode-a.efi  (untouched)
loader/loader.conf          default powernode-a*      (untouched)
```

The upgrade had replaced the firmware's removable-media bootloader — systemd-boot — with
the payload. `/EFI/Linux/` and `loader.conf` were pristine because **systemd-boot never
ran**. No boot counter, no one-shot, no default-entry fallback can engage when the thing
that implements them has been overwritten.

Why that path was taken:

```go
// agent/internal/bootslots/bootslots.go
const loaderGUID = "4a67b082-0246-4e07-9e78-2c9f24a68a41"   // WRONG

func BootedViaSystemdBoot() bool {
    _, err := os.Stat("/sys/firmware/efi/efivars/LoaderInfo-" + loaderGUID)
    return err == nil
}
```

The real systemd-boot Boot Loader Interface vendor GUID is
**`4a67b082-0a4c-41cf-b6c7-440b29bb8c4f`** — only the first group matched. That `Stat`
could never succeed on any node, so the predicate was permanently `false`, and
`bootupgrade.Apply` fell through to `espwrite.WriteUKI` → `installUKI`, the
bootloader-overwriting writer.

Verified directly: on the live node `LoaderInfo-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f`
**is present** and `bootctl status` reports `systemd-boot 255.4` with `✓ Boot counting`.
The node genuinely booted via systemd-boot; the check simply asked the wrong question.
Confirmed again by `strings` on both binaries: the deployed agent contains the wrong
GUID, the rebuilt one the correct GUID.

### Two callers, both boot-critical

- `bootupgrade.go:141` (`Apply`) → the bricking legacy write.
- `bootupgrade.go:172` (`ConfirmBoot`) → early-returns, so **no slot is ever blessed**.
  The INV-4 health-earned-LKG machinery is equally dead.

### Why it survived review

The string `4a67b082` appeared **exactly once** in the entire repository — the constant
itself. Nothing asserted it against a real efivars filename, so every unit test of the
A/B logic passed while the production predicate was always false. A constant that is only
ever compared to itself is not tested.

## Invariant impact

- **INV-3 (rollback below the payload) — STRUCTURALLY DEFEATED.** Rollback cannot be
  below the payload when the upgrade overwrites the rollback machinery *with* the payload.
- **INV-4 (good is EARNED) — NEVER ACTIVE.** `ConfirmBoot` was short-circuited by the same
  predicate, so no slot was ever blessed by a health gate.
- **INV-2 (boot ≠ network) — UNTESTED.** The run never reached the point of proving it.

## Blast radius avoided

P1-d's plan is *"deliver v28 to ops-hub-A via pull-reconcile + boot-counter rollback."*
Executed against ops-hub or ops-hub-B, this would have bricked a live control-plane node
and required exactly the host-side offline `/persist` surgery the campaign exists to
eliminate. The INV-10 rule that a class stays un-earned until its undo path is exercised
under injected failure — on a throwaway, human-observed — is the only reason this landed
on VM 9002 instead.

## The fix

1. `loaderGUID` corrected to `4a67b082-0a4c-41cf-b6c7-440b29bb8c4f`.
2. `efivarsDir` made an overridable package var so detection is testable, plus two
   regression tests: one pinning the constant against an independently-transcribed spec
   value, one creating the real efivar name in a temp dir and asserting detection fires.
   Both were confirmed to **fail** against the original GUID before the fix was applied.
3. **`Apply` now fails closed.** A node without an A/B layout refuses the upgrade instead
   of overwriting its bootloader. A stuck node beats a bricked one.
4. **`espwrite.WriteUKI` / `installUKI` deleted outright.** They were unreachable after
   (3), and leaving the exact primitive that bricked a node available for future rewiring
   is a footgun — its own doc comment ("no A/B, but no brick either") is what justified
   the path in the first place, and it was wrong.

## Standing caveats

- **The A/B path has still never run successfully in production.** Fixing the predicate
  makes `WriteUKISlot`, `bootctl set-oneshot`, `BlessSlot`, `CleanSlot` and
  `SlotGoodExists` reachable **for the first time ever**. They are unproven code, not
  known-good code. Re-running the P0-b proof is mandatory, not a formality.
- **INV-4 remains entirely unproven.** This round was Variant A (kernel-DOA) only, which
  at best demonstrates INV-3. Variant B — the design's own *primary* case, the one that
  exercises the health-gated bless — was never built.
- **Recovery required host-side offline surgery** (stop VM, mount ESP from the hypervisor,
  restore `BOOTX64.EFI` from `.bak`). That is precisely the failure mode RCP exists to
  remove, and it is only available because the node is a VM on a hypervisor we control.

## Evidence

- Serial capture (1.7 MB, all 48 boots): `rna:/root/9002-serial-p0b-FAILED.log`
- Broken artifact as written to the boot path: `/EFI/BOOT/BOOTX64.EFI.broken-uki` on
  VM 9002's ESP
- Staged UKI + valid cosign bundle retained at `/persist/cache/boot-image/` for the re-run

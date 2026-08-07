# Live Recompose: Adding/Removing Overlay Lower Layers Without Reboot

**Date**: 2026-08-06
**Status**: Phases 1–2 implemented in `extensions/system/agent` (same day, see §7);
Phase 3's beneath-swap primitive implemented and integration-verified on kernel 6.8;
the prefix-union packaging migration remains a follow-on campaign.
**Scope**: `extensions/system/agent` (pivot-booted nodes, `RootModeNative`)

## 1. Problem

On a pivot-booted node, `/` **is** the boot-time composed overlayfs union:
erofs module blobs loop-mounted at `/run/powernode/modules/<digest>` form the
`lowerdir` stack, a 512 MB tmpfs at `/run/powernode/scratch` provides
`upperdir`+`workdir`, and `systemctl switch-root` pivots into the merged view
(`agent/internal/mount/overlay.go`, `agent/internal/boot/boot.go`).

Post-boot, the lower stack is frozen. The union-skip block in
`RunOnce` (`agent/internal/runtime/reconcile.go:536`) deliberately never
re-extends `/`'s lowerdir, so **adding a module to or removing a module from
the composition requires a reboot**. We want recompose-without-reboot:
seamless module add/remove on a live node.

## 2. What already works live (more than the folklore says)

The agent already closes most of the *update* half of this gap:

- **Module version change (same ID, new digest)**: `hotReconcileIfNeeded`
  (`reconcile.go:958`) copies the new erofs content through the live merged
  view — every write is a copy-up onto the tmpfs upper that shadows the old
  lower (`hotreconcile.go`, `SyncModuleFilesToRoot`). Deletions are handled by
  `hotprune.go`: each candidate path is **re-resolved against the surviving
  layers in overlayfs priority order** — contested paths are rewritten from
  the surviving winner, sole-owned paths are unlinked (the whiteout is the
  desired effect). Units hot-restart via `AttachServices`.
- **Module add (new ID)**: partially works by accident — a fresh attach on
  tick 2+ flows through the same `SyncModuleFilesToRoot` copy. But it has a
  **priority-inversion bug**: the sync copies the *added* module's files
  unconditionally, and a copy-up in upper beats every lower layer. A
  low-priority addition that ships a path a high-priority existing module also
  ships will wrongly win. (The existing prune logic knows how to resolve
  winners; the add path just doesn't use it.)
- **Module remove (leaving the composition)**: explicitly out of scope today.
  `captureOutgoingPaths` (`reconcile.go:1040`) only inventories same-ID
  successors; a leaver's units stop and its erofs unmounts, but its files
  keep being served by `/` until reboot.
- **`reboot_required` modules** (e.g. `base-os-ubuntu-noble`): never
  hot-applied by design; surface `reboot_pending`.

So the real gap is narrower than "can't recompose": it is (a) removal of
leavers, (b) winner-correct addition, (c) an upgrade path for
`reboot_required` layers, and (d) the tmpfs upper as a RAM budget for all of
the above.

## 3. Hard kernel constraints (what is impossible)

These bound the solution space; every option below is shaped by them.

1. **A mounted overlayfs's lower stack cannot be changed.** `mount -o
   remount,lowerdir=...` is silently ignored; the new-mount-API
   (`fsconfig`) `lowerdir+` option builds the list incrementally *at mount
   creation only* — there is no `FSCONFIG_CMD_RECONFIGURE` support for lower
   layers. (The comment in `overlay.go:97` claiming `lowerdir+=` can "APPEND
   on 5.18+" overstates this — it is a creation-time option, not a live
   append. Fix the comment when next touching that file.)
2. **Modifying a lower directory underneath a mounted overlay is undefined
   behavior** (documented in `Documentation/filesystems/overlayfs.rst`).
   The "reserve an empty dynamic lowerdir slot and populate it later" trick
   is therefore unsound — dentry caching makes new lower content appear
   unreliably or not at all. Rejected.
3. **`/` itself cannot be atomically swapped for running processes.** Even
   with `MOVE_MOUNT_BENEATH` (kernel 6.5+) + lazy detach, every existing
   process's root `struct path` pins the old mount; their absolute lookups
   keep resolving through the detached old union forever. Swapping `/` for
   *everyone* requires re-executing userspace (that is what
   `switch-root`/soft-reboot are). So "mount a new union beneath `/`" gives a
   permanent split-brain, not a recompose. Rejected as a direct mechanism —
   but the same primitive works perfectly for **submounts** (see Option C).
4. **upperdir/workdir sharing between two overlay mounts is undefined** —
   which is exactly why the union-skip block exists. Any shadow-union scheme
   needs its own scratch mount.

Platform invariants to preserve: desired state keeps coming from module
assignments; `pending_compose` still stages the *true* lowerdir list for next
boot; LKG/boot-confirm semantics untouched. Live recompose is runtime
materialization toward the same desired stack — reboot always converges to a
clean compose (the tmpfs upper vanishing on reboot is a feature, not a bug).

## 4. Options

### Option A — Finish the materialized-recompose machinery (recommended first)

Treat the tmpfs upper as what it already de-facto is: **a materialized diff
between the boot-time stack and the current desired stack.** Extend the
existing hot-reconcile to full add/remove parity:

1. **Remove**: extend `captureOutgoingPaths` to also inventory modules
   leaving the composition (not just same-ID successors), then run the leaver
   through `PruneRemovedFiles` with the surviving-layer resolution it already
   implements. The doc-comment's stated reason for excluding leavers ("racing
   an operator mid-reassignment") becomes a policy gate, not a mechanism gap:
   e.g. only prune leavers whose assignment removal is `confirmed`/settled on
   the platform side, or after N stable ticks.
2. **Add (winner-correct)**: before `SyncModuleFilesToRoot` copies a path of
   a newly *added* module, resolve the union winner for that path across the
   full desired stack (same highest-priority-first walk as
   `survivingLayerDirs`) and copy the **winner's** content — or skip when the
   live view already serves the winner. This reuses the exact resolution
   logic `hotprune.go` was built on and closes the priority-inversion bug,
   which is worth fixing even independently of this design.
3. **Scratch budget guard**: before materializing, compare the projected
   copy-up size (sum of the delta's file sizes — cheap, the erofs is mounted)
   against tmpfs headroom (`statfs` on `/run/powernode/scratch`). Refuse with
   a clear `recompose_needs_reboot` signal instead of ENOSPC-ing the live
   root's upper mid-copy. Make the 512 MB scratch size a platform-delivered
   knob rather than a constant.
4. **Convergence audit**: after materializing, the merged view should equal
   the tree a fresh compose of the desired stack would produce. Spot-check by
   hashing a sample of contested paths against the resolved winners; surface
   drift via the existing `hot_prune_contested`-style signals.

- **Downtime**: only the affected module's own units restart. Nothing else
  notices.
- **Cost**: RAM for the copied delta until next reboot; walk/copy time for
  large modules.
- **Risk**: moderate — the subtle half (whiteout vs. restore) is already
  built and battle-tested; this is composition of existing pieces.
- **Limitations**: `reboot_required` layers stay excluded (correctly);
  the materialized state is not the "real" stack (debugging must remember
  upper can shadow lowers — but that is already true today).

### Option B — Soft-reboot tier for base-layer changes (recommended second)

For changes Option A cannot honor (`reboot_required` modules, scratch-budget
refusals, or operator-requested "clean" recompose): compose the new union at
`/run/nextroot` — the agent already composes at an arbitrary sysroot
(`ComposeForPivot(ctx, sysroot)`) — then `systemctl soft-reboot`
(systemd ≥ 254; noble ships 255/256). Userspace shuts down, systemd pivots
into `/run/nextroot` and re-executes as PID 1 in the new root; **the kernel,
and mounts under `/run`, survive** — no firmware, no initramfs, no
re-enrollment, no disk-image A/B cycle. Downtime is seconds (service
stop/start) instead of a full boot chain.

This converts today's binary "hot or full-reboot" into a three-tier ladder:
materialize (A) → soft-reboot (B) → full reboot (A/B slot upgrade, unchanged).

Verification needed before committing (see §6): exact mount-survival
semantics for `/persist` and the erofs loop mounts across soft-reboot, and
interaction with boot-confirm/LKG (a soft-reboot is *not* a boot-slot event —
the health gate must not re-arm or bless anything).

### Option C — Beneath-swappable per-prefix unions (the architectural end-state)

The reason recompose is hard is that the union is mounted at `/`. If the
composed union instead lived on **submounts** (the systemd-sysext model:
extensions merge into `/usr` + `/opt` via overlay, root stays a thin static
skeleton), then recompose becomes a genuine atomic lowerdir swap:

1. Compose the new union with the new module set (new overlay mount via
   `fsopen("overlay")`/`fsconfig`/`fsmount` — all in `golang.org/x/sys/unix`,
   already in `agent/go.mod`).
2. `move_mount(MOVE_MOUNT_BENEATH)` it under the existing `/usr` union
   (kernel ≥ 6.5; noble = 6.8 ✓), then lazy-detach the top mount. This is the
   exact use case the kernel feature was merged for (race-free
   `systemd-sysext refresh`).
3. Existing processes' roots never move (they sit on the unchanging root
   mount), so lookups cross into the new union immediately; open fds and
   running binaries pin old inodes via the detached mount until process exit
   — standard deleted-file semantics. Restart affected units; done.

- **No copying, no tmpfs growth, atomic, O(1)** regardless of module size —
  true add/remove of lower layers.
- **Cost**: a real architectural migration. Modules today ship whole-root
  trees (`/etc` skeletons, `/usr`, `/opt`, arbitrary paths); content would
  need to be split into swappable-prefix content (`/usr`, `/opt`, `/srv`)
  vs. rendered state (`/etc` is already largely agent-rendered:
  `etcidentity`, `etcsudoers`, unit files — a confext-style `/etc` overlay or
  plain rendering both work). Boot flow, hotreconcile/hotprune, and module
  packaging all change. Retires the file-copy machinery once complete.
- Fits the RCP-v2 / component-per-instance north star; propose as its own
  campaign, not a quick win.

### Option D — Shadow-union chroot attach (creative middle path, situational)

The cloud-VM path already runs module services chrooted into `/sysroot`
(`AttachServicesMode`, chroot mode) — and unlike `/`, **`/sysroot` can be
freely re-mounted post-boot** with a fresh lowerdir (that is precisely what
`MountUnion`'s umount+remount does on cloud hosts). On a pivot node, a newly
added module could therefore be attached by composing the full desired union
at `/sysroot` **with its own scratch mount** (avoiding the shared-upper UB
that motivated the union-skip block) and running the new module's units
chrooted into it, `/persist`+`/var` bind-mounted in.

- Gives true add/remove semantics for *new* services without touching `/`,
  zero copy for the unchanged layers (same erofs mounts, second union).
- Costs a permanent two-worlds split: host-view units vs. chroot-view units,
  divergent `/etc` rendering, harder debugging (`which world am I in` — we
  already pay this tax on cloud hosts, but mixing both modes on one node is
  new). Also RAM for a second scratch.
- Verdict: keep in the back pocket for the case Option A handles worst
  (very large added module that would blow the scratch budget) — it covers
  exactly that without a service interruption, where Option B costs a
  userspace bounce. Not worth the complexity as the primary mechanism.

### Rejected outright

- **Live lowerdir mutation / remount** — kernel no-op (constraint 1).
- **Reserved empty "dynamic" lowerdir slot populated post-mount** — undefined
  behavior (constraint 2); tempting and unsound.
- **Beneath-swap or `pivot_root` of `/` on a live system** — split-brain for
  every existing process (constraint 3).
- **fuse-overlayfs root** (userspace overlay could support dynamic layers) —
  FUSE for the rootfs is a performance and reliability non-starter.
- **Kernel patch for dynamic lower layers** — upstream has repeatedly not
  merged this; ovl inode/dentry state references layers by index, making it
  genuinely hard; unmaintainable fork.

## 5. Recommendation

Phased, each phase independently valuable:

1. **Phase 1 (Option A)** — extend hot-reconcile to leaver-prune +
   winner-correct add + scratch budget guard. Small, composes proven pieces,
   and fixes a real priority-inversion bug in today's add path. Delivers
   "seamless add/remove" for the app tier (everything not
   `reboot_required`) with per-module-only service impact.
2. **Phase 2 (Option B)** — `/run/nextroot` + soft-reboot as the middle tier
   for base-layer changes and budget refusals. Turns "reboot pending" into
   seconds.
3. **Phase 3 (Option C)** — migrate composition off `/` onto
   beneath-swappable prefix unions as part of the RCP-v2 arc. This is the
   durable answer; Phases 1–2 are how we get the capability now without
   betting the packaging model on it.

## 6. Verification checklist before implementation

- [x] Kernel ≥ 6.5 — verified empirically on the dev host (6.8): the
  beneath-swap integration test passes as root. Fleet-wide `uname -r`
  confirmation still worthwhile before relying on Phase 3 anywhere; the
  code also preflights at runtime (`KernelSupportsMoveMountBeneath`).
- [x] systemd ≥ 254 — enforced at runtime: `SoftRecomposePreflight` probes
  `systemctl --version` and refuses below 254.
- [x] **Mount survival — ASSUMPTION WAS WRONG; guard added 2026-08-07.**
  systemd does *not* preserve mounts across a soft-reboot by default.
  `systemd-soft-reboot.service(8)` guarantees only that "/run/ file
  system remains mounted"; everything else survives only if "configured
  to remain until the very end of the shutdown process" — meaning
  `DefaultDependencies=no` and no `Conflicts=umount.target`.
  **A live pivot node's `persist.mount` reports the opposite**
  (`DefaultDependencies=yes`, `Conflicts=umount.target`), so
  `soft-recompose --execute` as originally written would have landed in
  the new root with `/persist` unmounted: no enrolled PKI, no LKG/
  pending-compose, no durable `/var` — and on a self-hosted control
  plane, unrecoverable (it cannot re-enroll against itself).
  `SoftRecomposePreflight` now hard-refuses unless every entry in
  `CriticalSoftRebootMounts` is provably configured to survive; an
  unknown unit counts as "does not survive".
  **Unblocking work — DONE 2026-08-07**: `powernode-system-base` now
  ships `/etc/systemd/system/persist.mount.d/10-soft-reboot-survival.conf`
  (`DefaultDependencies=no`, which also drops the implicit
  `umount.target` conflict). Verified by installing that exact file on a
  live pivot node: properties flip as intended, the mount stays active,
  and the agent's real preflight goes from refusal to pass and back when
  removed. Drop-ins do apply to `persist.mount` even though it has **no
  unit file** — systemd synthesizes it from `/proc/self/mountinfo`, and
  the drop-in still shows up in `DropInPaths`.
  The module is `reboot_required: false`, so it reaches running nodes via
  hot-reconcile; systemd only picks the drop-in up after a
  `daemon-reload` or the next boot, and until it does the preflight keeps
  refusing (fails closed). **Still needs a module build + publish** to
  actually reach the fleet.
- [ ] **STILL REQUIRED before first fleet soft-reboot**: empirical
  verification on a scratch VM, now of the *post-drop-in* behavior —
  `/persist`, the erofs loop mounts under `/run/powernode/modules`, the
  live scratch tmpfs, and the rbinds staged inside `/run/nextroot`.
  Not attempted 2026-08-07: this dev box is itself a pivot-booted node
  (soft-rebooting it would take down the working environment) and has no
  KVM; no root channel to a disposable fleet VM was available (SSH gives
  unprivileged `pnadmin` with no sudo on both the CI-pool builder and
  ops-hub, and the PVE guest-agent route needs a Rails console that
  itself needs root). Needs either a NOPASSWD-sudo grant on a scratch
  node, PVE credentials, or a local KVM-capable host.
- [x] LKG/boot-confirm interplay — addressed structurally: the capturer
  snapshots the breadcrumb once at entry, and soft-recompose withholds the
  breadcrumb until execute time (`BreadcrumbSink`), restoring the prior
  one if `systemctl soft-reboot` itself fails. A/B interplay: preflight
  refuses while a slot upgrade is armed (`bootslots.Pending`).
- [ ] Measure real module delta sizes vs. the 512 MB scratch (hub-backend is
  the stress case). The budget guard (default 64 MiB floor,
  `ReconcilerConfig.ScratchMinFreeBytes`) and the now-configurable
  `Overlay.ScratchSize` make both ends tunable; sizing data still wanted.
- [x] `overlay.go` comment corrected (`lowerdir+` is creation-time only).

## 7. Implementation record (2026-08-06)

All in `extensions/system/agent`, uncommitted on the submodule's `develop`:

**Phase 1 — materialized recompose** (`internal/runtime`)
- `SyncModuleFiles` (hotreconcile.go) supersedes `SyncModuleFilesToRoot`
  (kept as a wrapper): winner resolution via `SyncOptions.HigherLayers`
  (fixes the hot-add priority inversion, IMP `019fd966`, red-first test in
  `hotreconcile_winner_test.go`) + scratch budget guard
  (`SyncOptions.MinFreeBytes`, `ErrScratchBudget`, statfs on the overlay
  root reports the upper tmpfs).
- Leaver prune (hotleaver.go): a module leaving the composition is
  inventoried pre-unmount, recorded under `/run/powernode/pending-prune/`,
  armed on the next tick, and pruned one tick later through the existing
  `PruneRemovedFiles` surviving-layer resolution. Reappearance cancels;
  a missing desired layer defers the whole pass; `reboot_required`
  leavers surface `reboot_pending` instead.
- New signals: `reconciler:recompose_budget`, `reconciler:hot_sync_contested`,
  `reconciler:capture_leaver`, `reconciler:leaver_prune`.
- `Overlay.ScratchSize` knob (mount/overlay.go), default unchanged at 512m.

**Phase 2 — soft-reboot tier**
- `SoftRecomposePreflight` + `SystemdVersion` (runtime/softreboot.go):
  native-mode-only, systemd ≥ 254, refuses while an A/B slot upgrade is
  armed.
- `mount.NextrootLayout(gen)`: `/run/nextroot` sysroot with a per-prepare
  scratch tmpfs (never shares upper/work with the live root); module
  mounts + blob cache shared.
- `NewPivotComposerAt` + `ReconcilerConfig.BreadcrumbSink`: the nextroot
  compose reuses `ComposeForPivot` verbatim but hands the boot breadcrumb
  to the caller instead of writing it — committed to disk only at execute
  time (soft-reboot keeps the kernel boot ID, so an on-disk breadcrumb for
  an unexecuted prepare could be promoted by the LKG capturer).
- CLI: `powernode-agent soft-recompose` (prepare + report; `--execute`
  fires `systemctl soft-reboot`), reusing `bindAndCheckSysroot` +
  `ensureCanonicalInit` from the switch-root path. Hot-tier refusal
  messages now name the command.

**Phase 3 — beneath-swap primitive** (`internal/mount/beneath.go`)
- `ComposeOverlayFD` (fsopen/fsconfig `lowerdir+`/fsmount; upper-less =
  read-only union) + `SwapBeneath` (`move_mount(MOVE_MOUNT_BENEATH)` +
  lazy detach of the old top) + `KernelSupportsMoveMountBeneath`.
- `MOVE_MOUNT_BENEATH` (0x200) is defined locally until x/sys ships it.
- **Integration-verified as root on kernel 6.8** (`TestSwapBeneath_Integration`):
  atomic lookup flip, shared lower preserved, held-open fd keeps the old
  union. What remains for Phase 3 is the packaging/boot migration to
  prefix unions (`/usr`, `/opt` composed as submounts; `/etc` rendered),
  which should be run as its own campaign per §4 Option C.

## 7b. Independent critic review (2026-08-07) — OPEN ITEMS

Two independent critics reviewed the boot-critical paths (the standing
two-critics rule). Five defects were found and fixed in `4a47f141`; the
worst was a **node-destroying** bug reachable from this feature's
documented happy path (binding `/run` into a nextroot that lives inside
`/run` made a later `umount -l` detach the running root's overlay upperdir
and every module layer — reproduced in a mount namespace, with a control).

**These remain OPEN and are blocking for `--execute` on real hardware:**

1. **`CriticalSoftRebootMounts` guards the wrong unit.** A bind survives
   its source being unmounted, so tearing down `persist.mount` at
   `umount.target` is harmless — what actually carries `/persist` into the
   new root is `run-nextroot-persist.mount`, which is now the *sole*
   carrier and is unchecked. Meanwhile `run-powernode-scratch.mount` and
   every `run-powernode-modules-*.mount` report
   `DefaultDependencies=yes` + `Conflicts=umount.target` on a live node —
   they fail the code's own survival criterion and are not in the list.
2. **Highest-stakes open question**: does systemd exempt mounts under
   `/run/nextroot/**` from `umount.target`? If not, `--execute` lands in
   the new root with `/persist` gone — the exact unrecoverable outcome the
   guard exists to prevent, with the preflight reporting OK. Needs the
   scratch-VM check.
3. **Preflight tests the predicate the codebase documents as wrong**:
   `bootslots.Load().Pending` instead of
   `bootupgrade.ConfirmNeeded(bootedGitSHA)`. A node in the
   reconcile-owed state passes the preflight while running an unblessed
   slot. (`bootconfirm.go` explains why `Pending == ""` is not "nothing to
   do".)
4. **A budget-aborted sync never re-converges.** The module is recorded
   fully attached before the sync runs, so the next tick sees no drift and
   never retries; `recompose_budget` fires once and goes silent, which
   reads as resolved. `fs.SkipAll` also splits the module at an arbitrary
   alphabetical boundary with units already restarted against the mix.
5. **`Overlay.ScratchSize` is dead** — no caller sets it, including the
   nextroot compose, which is partly why the soft-reboot tier exists.
6. After a *successful* soft-reboot, `/run/nextroot` is probably still a
   mountpoint in the new root, so the next `soft-recompose` may hit the
   fixed-but-related teardown path with no prior prepare. Unverifiable
   without performing a real soft-reboot.

Also worth recording, because the current safety model implies the
opposite: **a composed overlay keeps serving after its lower and upper
mountpoints are unmounted** (overlayfs clones its layers privately). That
is why the critical bug was silent, and it means `umount.target` tearing
down layer mounts does not by itself destroy the new root.

## 8. Related memory / prior art

- Memory: "Live module refresh doesn't remount on pivot" — superseded in
  detail by §2 (content updates DO hot-apply; the gap is layer add/remove).
- Memory: "/ is a RW overlay — hot-patch composed files + restart rails" —
  the manual stopgap that Option A formalizes and makes winner-correct.
- systemd-sysext / confext refresh and kernel `MOVE_MOUNT_BENEATH` (6.5,
  merged for exactly this use case) — prior art for Option C.
- composefs (EROFS metadata + fs-verity content addressing) — natural later
  refinement of Option C's per-prefix images; not needed for any phase here.

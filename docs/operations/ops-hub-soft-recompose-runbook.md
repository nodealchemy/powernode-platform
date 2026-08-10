# Runbook — ops-hub soft-recompose (devpin dedup + system-base bump)

**Status**: scheduled, not yet executed · **Node**: ops-hub (VM 600 on dna, 10.125.0.227)
**Prepared**: 2026-08-10 · **Requires**: an operator present for the whole window

## Why this exists

ops-hub has logged `reconciler:self_host_detach_refused` every ~60s since
**2026-08-09 23:58**. Two modules are attached but no longer desired:

| module | id | note |
|---|---|---|
| `postgres-primary-vm104-devpin` | `019f7cb5-38d6-…` | duplicate; **no running unit** |
| `runtime-ruby-vm104-devpin` | `019f7cb5-38df-…` | duplicate; ships no services at all |

The live database is already served by the **canonical** module —
`powernode-019f73f9-ef17-…-postgres.service` is the running unit, and
`019f73f9-ef17` is `postgres-primary`, not the devpin. So this is **removal of
dead weight, not replacement of anything live**. The `vm104` names are leftovers
from a deleted VM id.

The agent will not live-detach service-bearing modules on a node that hosts its
own platform (correct: that is the 2026-07-28 self-detach outage), so it defers
to a recompose. Until the recompose happens, **every unplanned reboot exercises
this staged composition unsupervised** — which is the actual reason to schedule
it rather than leave it.

### One thing that DOES change

The staged set carries a **newer `powernode-system-base`** (same module id
`019f73f9-ef60`, digest `558346cc…` → `37e65e58…`). That module ships the agent
binary, so the recompose also upgrades the running agent. Expected, health-gated,
and covered by the fallback below — but know it going in.

## Why soft-recompose rather than a reboot

`powernode-agent soft-recompose` composes the desired set at `/run/nextroot`
using the same code path a cold boot uses, then switches via
`systemctl soft-reboot`: userspace only, same kernel, no bootloader, no
initramfs, no re-enrollment. Downtime is one service bounce. It avoids the whole
cold-boot window — no cidata enumeration race, no DNS-at-boot dependency.

A supervised full reboot reaches the same end state and is an acceptable
fallback; it is strictly more exposure, not more correctness risk.

## Preflight — all verified 2026-08-10, re-verify on the day

| gate | requirement | last checked |
|---|---|---|
| systemd | ≥ 254 | **255** ✓ |
| `/persist` survives soft-reboot | `DefaultDependencies=no`, no `Conflicts` | ✓ |
| pivot-composed node | required | ✓ (prepare succeeded) |
| no A/B boot-image upgrade armed | required | preflight enforces |
| prepare exit code | 0 | ✓ |

Preflight **fails closed**: if any gate is unmet the command refuses before
touching anything.

## Procedure

Access (QGA payloads must stay under ~500 bytes — keep each exec small):

```
ssh admin@dna → sudo -n qm guest exec 600 -- /bin/sh -c '<small command>'
```

1. **Snapshot the baseline** so "healthy after" is comparable:
   `systemctl list-units 'powernode-*' --state=running` (expect 9),
   `curl -s -o /dev/null -w %{http_code} http://127.0.0.1:3000/up` (expect 200).
2. **Confirm no deploy is mid-flight** — no build batch running, no module
   sync in progress (`journalctl -u powernode-agent --since -5min`).
3. **Prepare** (safe, abandonable, no service impact):
   `powernode-agent soft-recompose`
   Expect `PREPARED — /run/nextroot holds the freshly composed union.` and a
   note that the boot breadcrumb was deliberately NOT written.
4. **Review the prepared root** before switching:
   confirm the four core markers and both extension markers are present under
   `/run/nextroot/opt/powernode/...` — this is what you are about to switch
   into. If a marker is missing, STOP and abandon; do not execute.
5. **Execute**, with the console reachable:
   `powernode-agent soft-recompose --execute`
6. **Verify** (allow ~30–60s; `/up` may refuse connections briefly while Rails
   boots — that is expected, not failure):
   - 9 `powernode-*` units running, `powernode-agent` active
   - `/up` → 200
   - `journalctl -u powernode-agent --since -5min | grep self_host_detach_refused`
     → **no output** (this is the success signal)
   - the six deploy markers still present
   - `systemctl list-units 'powernode-*'` shows no `019f7cb5-38d6/38df` units

## If it goes wrong

- **Preflight refuses** → nothing happened. Fall back to a supervised full reboot.
- **Compose fails** → error returned, node still running the old composition.
  Nothing happened.
- **Post-switch userspace unhealthy** → `qm reset 600` from dna. The cold boot
  tries the pending set (`PendingMaxTries=2`, attempt counter persisted before
  composing), and on repeated failure falls back to the **frozen LKG**, i.e.
  today's working devpin composition. The devpin blobs are still cached —
  nothing prunes the module blob cache — so the fallback is intact.
- **Node unreachable** → serial console: `qm terminal 600`.

## Proposed window

**Tuesday 2026-08-11, 07:00–08:00 UTC** — before the working day, operator
present, no build or deploy in flight. Needs ~15 minutes of actual work; the
hour is headroom for the fallback path.

Do **not** run it while a module build is dispatched or a deploy is syncing.

## Explicitly NOT part of this window

- Do not "repair" the composition by flipping `NodeModuleAssignment` rows. That
  was attempted on 2026-08-10 and reverted: it does not remove the conflict, it
  only inverts which duplicate is slated for drop, and it briefly staged the
  canonical (correct) copy for removal. Desired state is already right.
- Deleting the devpin `NodeModule` rows is hygiene for afterwards, not now.

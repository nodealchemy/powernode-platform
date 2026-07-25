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
| 2 | `ops.powernode.org` resolves to `10.125.1.37` (the Gitea docker host) and **nothing serves it** — yet it is the workflow's hardcoded default | DNS + `build-disk-image.yaml:390,551` | CI silently falls back to a dead host whenever the secret is unset | ⚠️ open — needs a DNS record or the default changed |
| 3 | **CI builders enrol to dev**: `SiteSetting[system.ci_builder.enroll_platform_url] = https://dev.ipnode.us` | platform setting | **Build fleet cannot enrol.** You lose the ability to build the images needed to fix it — the circular dependency P7 exists to break | 🔴 **blocks dev-off** |
| 4 | `POWERNODE_DISK_IMAGE_WEBHOOK_URL` — the call that creates the `DiskImagePublication` | Gitea secret (value masked) | New images publish to the wrong plane. Strongly implied by dev's DB holding the current publications | 🔴 open — **repoint with #1 or CI is split-brained** |
| 5 | `reverse_proxy_url_config.trusted_hosts` includes `dev.powernode.org` / `dev.ipnode.us` | AdminSetting | Cosmetic; stale entries only | minor |

### Note on #4 — a self-inflicted split

Repointing #1 to ops-hub while #4 still points at dev leaves CI **half-migrated**: it fetches
registry config and authenticates against ops-hub, then announces the finished image to dev.
Either repoint both or neither. This is exactly the failure mode the "name things, never pin
addresses" rule is meant to prevent, and it was introduced *by the migration itself* — worth
recording as evidence that partial cutovers are their own hazard.

## Still to check

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

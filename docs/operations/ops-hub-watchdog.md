# ops-hub External Watchdog + qmstart Auto-Retry

> Status: active (P0-a of the Resilient Control Plane v2 campaign)

**When to use this runbook**: deploying or tuning the external dead-node monitor for
ops-hub (VM104), understanding why it exists, or arming the qmstart auto-retry after
operator sign-off.

## Contents

- [Why this exists](#why-this-exists)
- [What was verified live (boot target)](#what-was-verified-live-boot-target)
- [Fleet topology investigation](#fleet-topology-investigation)
- [The external watchdog](#the-external-watchdog)
- [Monitoring multiple targets (e.g. ops-hub-B)](#monitoring-multiple-targets-eg-ops-hub-b)
- [Detection timing budget](#detection-timing-budget)
- [The qmstart auto-retry (ships dry-run; ARMED on `dna`)](#the-qmstart-auto-retry-ships-dry-run-armed-on-dna)
- [Arming qmstart-retry](#arming-qmstart-retry)
- [Existing infrastructure reused vs. not used](#existing-infrastructure-reused-vs-not-used)
- [Open decisions for the operator](#open-decisions-for-the-operator)

## Why this exists

ops-hub (VM104, `ops-hub.ipnode.us`, hosted on the Proxmox hypervisor `dna`) has
repeatedly become its own single point of failure:

- **Frozen-LKG boot trap**: once `meta.json`'s `platform_url` pointed at ops-hub
  itself, the pre-pivot live-fetch fails DNS resolution every boot and permanently
  falls back to a frozen known-good snapshot (see memory
  `ops-hub-lkg-self-pointed-dns-brick-risk`). This is a known, accepted steady state
  (by design, per the #39 Level-1 survival architecture) — but it means no external
  system should assume ops-hub can self-report its own health after a repoint.
- **2-day unnoticed outage (2026-07-21 -> 2026-07-23)**: a transient `dna-data` NFS
  blip failed a manual `qmstart 104`. Nothing retried it. Because ops-hub had already
  been repointed to heartbeat only to itself, dev's own fleet dashboard showed it
  `stopped` "by design" and alerted nothing (see memory
  `ops-hub-unmonitored-after-self-repoint`).

This is increment **P0-a** of the RCP v2 campaign's own over-engineering check: ship
the cheap fix (confirm the boot target is already local+pinned, add cheap external
monitoring) before investing in the fuller quorum/consensus work sequenced afterward
(P1+). Full design: `~/.claude/plans/campaign-reciprocal-control-plane.md`.

## What was verified live (boot target)

Acceptance criterion: "boot target confirmed local + pinned, no DNS/fetch dependency
on the critical boot path." Rather than trust the incident memory's account (which is
itself point-in-time), this was independently re-verified live via read-only SSH
(`pnadmin@ops-hub.ipnode.us`, unprivileged, no sudo) on 2026-07-23:

| Check | Result |
|---|---|
| `/proc/cmdline` | `console=tty0 console=ttyS0,115200 powernode.boot=1 ip=dhcp powernode.image_git_sha=a60b0a0d4da8feba5271e6990929da974a836af6` — boot identity is a pinned content hash (`image_git_sha`), not a live manifest URL. `ip=dhcp` only requests an address; nothing on the cmdline forces a fetch to complete before boot proceeds. |
| `mount` (root fs) | `overlay on /` composed from a stack of `lowerdir=/run/powernode/modules/sha256_<digest>:...` — the live root is an overlayfs of content-addressed, already-resident module directories, i.e. a locally composed image, not something assembled by contacting a remote server during this boot. |
| `mount` (`/persist`) | `/dev/sda2 on /persist type ext4` — local disk, not NFS/network storage. |
| `systemctl list-units` | `powernode-network-reload.service` is `active/exited` — this is the documented **post-pivot** DNS fix-up (re-push DNS to resolved after switch-root). Its presence and success confirm DNS dependency is scoped to *after* the critical boot path, not blocking it. |
| `uptime` | ~6h at time of check — a recent, successful, ordinary boot, not an artificially-held-up test system. |

Not independently re-read this session (appropriately access-restricted, not a gap in
the mechanism): `/persist/var/lib/powernode/meta.json` and `assignment-lkg.json` are
root-only (0600-class perms, consistent with living alongside the agent's mTLS
private key material per the `powernode-agent` bootstrap pattern) and the unprivileged
`pnadmin` account used for this check cannot read them, nor is `journalctl`
readable without elevated group membership. The incident memory's own 2026-07-20
real-reboot test already exercised these files directly and confirmed the LKG
fallback path works end-to-end (8/8 units, `/up`=200); nothing observed in this
session's live check contradicts that. **Conclusion: boot target is local + pinned;
no network dependency on the critical (pre-pivot) boot path, confirmed independently
from a different angle (kernel cmdline + mount table + unit ordering) than the prior
DNS-error-log-based verification.**

## Fleet topology investigation

The task specified the watchdog should run from **opn-1, edge, or dev-cell** —
"whichever is actually reachable/appropriate." This was investigated in two passes.

**Pass 1** (no fleet credentials yet, from the `dev` box only): none of the three
could be identified — no DNS, no SDWAN peer (both networks showed `peer_count: 0`),
not in the platform's `System::Node`/`NodeInstance` registries, no PTR records among
23 live hosts found via a full `nmap -sn` sweep of `10.125.0.0/24`, and the `pnadmin`
fleet SSH key wasn't accepted by any unidentified host. This was reported as a
flagged decision rather than guessed.

**Pass 2** (after the coordinator provisioned real cluster access —
`admin@dna` w/ passwordless sudo, and root-to-root SSH trust from `dna` to
`fna`/`lna`/`rna`): the coordinator resolved all three, confirmed against the real
4-node Proxmox cluster (`ipnode`: dna/fna/lna/rna, `pvesh get /cluster/status`):

| Host | Resolution | Verdict |
|---|---|---|
| `opn-1` | VM **105** on `dna` (name `opn-1`, running) | **The operator's firewall — off-limits**, confirmed directly by the operator. Not a candidate. |
| `edge` | Not found anywhere in `pvesh get /cluster/resources --type vm` across all 4 nodes | Does not exist as a VM in the current cluster. Not a candidate. |
| `dev-cell` | VM **9000** on `dna` (`ops-hub-dev-cell-1784413717-instance-...`, running) | Exists and runs, but **on `dna`** — the same host as ops-hub itself. A watchdog there shares ops-hub's exact blind spot (total-`dna`-failure undetectable). Not a good choice for *this* probe's purpose, independent of reachability. |
| `rna` | Real Proxmox cluster member, `10.125.0.13`, **zero running VMs at the time of check** | Confirmed independent failure domain (distinct physical host, distinct `local-data` ZFS pool from `dna-data`). **Selected** — see below. |

**Resolution: deployed to a new VM (9001) on `rna`.** Cluster-wide VMID freeness was
verified immediately before creating it, both via `qm status 9001`/`9002` on `dna`
(exit 2, "Configuration file ... does not exist" — confirmed via
`pvesh get /cluster/resources --type vm`, the cluster-wide authoritative view) and by
grepping the platform's own `system_list_instances` output for any `9001`/`9002`
reference (zero hits). VMID 9002 (a concurrent throwaway from the parallel
`rcp-p0b-rollback-design` increment, also on `rna`) was left untouched throughout.

## The external watchdog

`scripts/monitoring/ops-hub-watchdog.sh` (+ `scripts/monitoring/systemd/powernode-ops-hub-watchdog.{service,timer}`).

Polls `https://ops-hub.ipnode.us/up` on a short interval (falls back to ICMP ping to
distinguish "host fully unreachable" from "host up, app-level failure"). Requires
`FAILURE_THRESHOLD` (default 3) consecutive failures before alerting, so a single
transient network blip between the watchdog host and ops-hub doesn't page anyone —
deliberately mirroring the fact that the real incident's root trigger *was* a
transient storage blip, so the design should not be trigger-happy on blips it can't
distinguish from real death, but must still close the loop when they persist.

On alert (and again on recovery), it fires three channels that degrade gracefully:

1. **journald/syslog**, tagged via `SyslogIdentifier=powernode-ops-hub-watchdog`
   and — because the shipped unit is literally named
   `powernode-ops-hub-watchdog.service` — this automatically satisfies the existing
   Promtail `powernode-journal` scrape job's `keep` relabel rule
   (`docs/operations/observability.md`) with **zero Promtail config changes**, so
   once the operator's Loki/Promtail/Grafana stack is running, these lines already
   flow in.
2. **Prometheus textfile-collector metric**
   (`/var/lib/node_exporter/textfile_collector/powernode_ops_hub_watchdog_${TARGET_NAME}.prom`,
   only written if that directory already exists) exposing
   `powernode_ops_hub_up{target="ops-hub"}` — plugs into the same Grafana/Prometheus
   stack that `observability.md` documents as the platform's intended alerting layer,
   once the operator adds an alerting rule on this metric. Filename is parameterized
   by `TARGET_NAME` specifically so a second concurrent instance monitoring a
   different target doesn't clobber this one — see
   [Monitoring multiple targets](#monitoring-multiple-targets-eg-ops-hub-b) below.
3. **Optional generic webhook** (`ALERT_WEBHOOK_URL` / `ALERT_WEBHOOK_TOKEN` in
   `/etc/powernode/ops-hub-watchdog.conf`) — a plain JSON POST to any receiver the
   operator already has (Slack incoming webhook, ntfy.sh, healthchecks.io,
   PagerDuty Events API, etc.). No-op if unset.

**Deliberately not wired to Powernode's own notification API.** MCP-first research
(this increment) traced `send_proactive_notification` and `report_issue` to
`Ai::AgentOutreachService`/`Ai::AgentObservation` — both are MCP-tool-only today,
with no REST controller wrapping them. The only token-authenticated *inbound*
webhook endpoints that exist (`ralph_loop_webhooks`, `chat/webhooks`,
`webhooks/git/:provider_type`) are built for unrelated purposes (triggering a Ralph
Loop, receiving chat messages, receiving git push events) and none create a
`Notification`/`Ai::AgentObservation`. Building a new token-authenticated "external
health alert" endpoint would be a reasonable follow-up but is new backend surface
beyond this increment's scope — flagged below rather than built silently.

### Monitoring multiple targets (e.g. ops-hub-B)

The target is **not** a SiteSetting or any DB-backed value — this script has no
Rails/API/DB access at all, by design (it has to keep working even if the entire
platform, including the DB it might otherwise read config from, is unreachable). It's
a plain shell `EnvironmentFile` at `$CONFIG_FILE` (default
`/etc/powernode/ops-hub-watchdog.conf`), which the systemd unit passes via
`EnvironmentFile=-/etc/powernode/ops-hub-watchdog.conf` (the leading `-` means
"don't error if absent").

The integration seam for a second target (e.g. once P1-a's ops-hub-B exists) is: a
**second config file + a second systemd service/timer pair pointing at the same
script**, e.g.:

```bash
# /etc/powernode/ops-hub-b-watchdog.conf
TARGET_NAME="ops-hub-b"
TARGET_URL="https://ops-hub-b.ipnode.us/up"   # or whatever B's real address is
TARGET_PING_HOST="ops-hub-b.ipnode.us"
```

```ini
# /etc/systemd/system/powernode-ops-hub-b-watchdog.service (copy of the shipped
# unit with two lines changed):
SyslogIdentifier=powernode-ops-hub-b-watchdog
EnvironmentFile=-/etc/powernode/ops-hub-b-watchdog.conf
ExecStart=/opt/powernode/scripts/monitoring/ops-hub-watchdog.sh --once
```

(plus a matching `.timer` — copy `powernode-ops-hub-watchdog.timer`, rename.)

Everything keyed by `TARGET_NAME` stays independent per instance: the state file
(`${STATE_DIR}/${TARGET_NAME}.state`) already was; **the Prometheus metric file
was NOT until this revision** — it was a static filename
(`powernode_ops_hub_watchdog.prom`) that a second instance with a different
`TARGET_NAME` would have silently overwritten on every run (both instances would
still log correctly and alert correctly via journald/webhook; only the Prometheus
metric surface would have been wrong — whichever instance ran last would clobber the
other's gauge). Fixed here to
`powernode_ops_hub_watchdog_${TARGET_NAME}.prom` — node_exporter's textfile
collector scrapes every `*.prom` file in the directory, so multiple per-target files
is the correct, supported pattern, not a workaround. Verified: two instances with
different `TARGET_NAME` (one pointed at the real ops-hub, one at a deliberately
unreachable address) now produce two independent files with correct, non-colliding
values; redeployed to the live VM 9001 instance (which now emits
`powernode_ops_hub_watchdog_ops-hub.prom` instead of the old static name).

If P1-a's design wants a single unified "which ops-hub instances are down" view
rather than N independent per-target files/timers, that's a small further step (e.g.
a `TARGETS` list the script iterates, or a wrapper timer that invokes the script once
per configured target) — not built here since only one target (ops-hub-A) exists
today; flagged as a natural extension point rather than speculatively built ahead of
need.

### Deployment (live, as actually run)

**Deployed and running**: VM `rcp-watchdog` (VMID **9001**) on `rna`, static IP
`10.125.0.150/24`, provisioned directly via `qm create`/`qm importdisk`/`qm set`
(no template existed in cluster storage; used a freshly-downloaded generic Debian 12
cloud image, `local-data` storage, `vmbr0` bridge — 1 vCPU / 1GB RAM / 8GB disk,
trivial footprint against rna's ~20 idle cores / ~50GB free memory at provision time).
Not tracked in Powernode's own `System::Node`/`NodeInstance` DB — it's a raw Proxmox
VM, reachable directly from `dev` (same `10.125.0.0/24` LAN) via the injected
`powernode-deploy` SSH public key, user `watchdog`.

**Gotcha hit and fixed**: the cloud-init `--nameserver` was initially set to
`127.0.0.53` (copied from *this session's own* `/etc/resolv.conf`) — that address is
`dev`'s own local `systemd-resolved` stub, meaningless on a different host. Fixed to
the real upstream resolver (`10.125.0.1`, found via `resolvectl status` on `dev`),
both live (`/etc/resolv.conf` on the VM) and persistently (`qm set 9001 --nameserver
10.125.0.1 --searchdomain ipnode.net`, so it survives a cloud-init re-run).

The `powernode-ops-hub-watchdog.timer` is enabled and active on this VM now,
confirmed firing every ~15-16s.

```bash
# Generic deployment steps (what the above amounts to on any host):
sudo mkdir -p /etc/powernode /var/lib/powernode-watchdog
sudo cp scripts/monitoring/ops-hub-watchdog.sh /opt/powernode/scripts/monitoring/
sudo cp scripts/monitoring/systemd/powernode-ops-hub-watchdog.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now powernode-ops-hub-watchdog.timer
# Optional tuning / webhook config:
sudo tee /etc/powernode/ops-hub-watchdog.conf <<'EOF'
# ALERT_WEBHOOK_URL="https://example.invalid/webhook"
# ALERT_WEBHOOK_TOKEN="..."
EOF
```

Manual one-off check: `scripts/monitoring/ops-hub-watchdog.sh --once` (safe to run
anywhere with network access to the target; writes state under `/var/lib/powernode-watchdog`
by default, or `$STATE_DIR` if overridden — useful for a non-root smoke test).

### Live detection test (real infrastructure, not synthetic)

Verified end-to-end against the actually-deployed VM 9001 and the actually-live
ops-hub — not a dev-box dry run with env-var overrides. Method: rather than stop the
live ops-hub VM itself (a real production-adjacent service with active state —
in-flight knowledge-migration dumps, live rails/sidekiq/postgres/redis/traefik — and
squarely the class of "could restart/reboot/reprovision a live node" this increment's
mandate reserves for explicit human sign-off, not a coordinating agent's say-so), the
new watchdog VM's own outbound path to ops-hub was blocked at the network layer
(`iptables -A OUTPUT -d 10.125.0.227 -j DROP` on VM 9001 only) — a condition
indistinguishable, from the watchdog's perspective, from ops-hub actually being down,
achieved without touching ops-hub or any other existing node.

| Event | UTC timestamp |
|---|---|
| Block applied | `2026-07-24T05:41:11.12Z` |
| **ALERT fired** (journald, real deployed timer/script) | `2026-07-24T05:41:52Z` |
| **Detection latency** | **41s** |
| Block removed | `2026-07-24T05:49:03.71Z` |
| **RECOVERED logged** (real, "after 30 failed check(s)") | `2026-07-24T05:49:15Z` |
| **Recovery latency** | **~12s** |

41s is comfortably under the 2-minute acceptance target (and better than the ~84s
theoretical worst case documented below — this run's timing within the poll cycle was
favorable). Confirmed clean afterward: `iptables -L OUTPUT` empty on the watchdog VM,
timer still `active`, state file reset to `consecutive_failures=0`,
`already_alerted=0`, metric file back to `powernode_ops_hub_up 1`.

## Detection timing budget

Acceptance: killed/unreachable ops-hub detected + alerted in **< 2 minutes**.

- Timer cadence: `OnUnitActiveSec=15s` (next run starts 15s after the previous one
  *finishes*, so pathological worst case includes check latency, not just the timer
  period).
- Per-check timeout: `CONNECT_TIMEOUT_SECONDS=3` (curl) + up to 3s ping = at most ~6s
  of check execution in the all-timeouts worst case.
- Worst-case cycle period: ~15s (timer) + ~6s (checks) ≈ 21s.
- `FAILURE_THRESHOLD=3` consecutive failures before alerting: 3 × 21s ≈ 63s, plus up
  to one more cycle of uncertainty for exactly when within a cycle the real failure
  began (+21s) ≈ **~84s worst case** — comfortably under the 120s target with ~36s of
  margin for scheduling jitter.

## The qmstart auto-retry (ships dry-run; ARMED on `dna`)

`scripts/monitoring/ops-hub-qmstart-retry.sh` (+ `scripts/monitoring/systemd/powernode-ops-hub-qmstart-retry.{service,timer}`).

> **Live state (verified 2026-07-26, not inferred):** the timer is active on `dna` and
> the arm marker `/etc/powernode/qmstart-retry.armed` is **present** — so on `dna` this
> is executing for real, not dry-running. The operator armed it 2026-07-25 after both
> logic branches were exercised against the live Proxmox CLI. The *code* default below
> is unchanged and still dry-run; arming is deployment state, held in a marker file on
> one host, and is invisible to this repo. Re-verify with
> `systemctl list-timers powernode-ops-hub-qmstart-retry.timer` and
> `test -f /etc/powernode/qmstart-retry.armed` rather than trusting this note.

Runs on the Proxmox hypervisor (`dna`) — needs local `qm`/`pvesm` CLI, unlike the
watchdog above which runs on a third-party host. Directly targets the 2026-07-21
incident: VM stopped + storage back online + nothing ever retried the start.

Logic per run (level-triggered, not edge-triggered — deliberately, so it keeps
self-healing across script/timer restarts rather than needing to catch a precise
storage-recovery transition):

1. `qm status <vmid>` — if already running, no-op.
2. If stopped: `pvesm status` for the configured storage (default `local-data` — it
   was `dna-data` until P0-c migrated ops-hub off NFS; the gate must name the storage
   the VM's disks actually live on, verified live 2026-07-25 via `qm config 104`) — if
   not active yet, log and wait for the next cycle.
3. If stopped AND storage active: retry candidate, rate-limited to
   `MAX_ATTEMPTS_PER_WINDOW` (default 3) per `WINDOW_SECONDS` (default 3600) so a
   start that keeps failing for an unrelated reason doesn't hot-loop — after the cap
   it logs "giving up, needs human" and stops trying until the window rolls over.

**Ships permanently in dry-run.** The script only executes `qm start` when **both**
of the following hold at once — the shipped systemd unit provides neither:

- invoked with `--execute`, **and**
- the marker file `/etc/powernode/qmstart-retry.armed` exists.

Absent either one, every run only logs `DRY-RUN (not armed): would run 'qm start
104'...`.

**Validated against the real Proxmox CLI on `dna`** (read-only; no `--execute`, no
marker file — dry-run mode makes execution structurally impossible regardless of what
it observes, so this was safe to run directly):

- `qm status 104` (real ops-hub, genuinely running) → correctly logged "already
  running -- nothing to do", exit 0.
- `qm status 100` (`ops-old`, a genuinely-stopped real VM, used only as a safe
  dry-run target — never started) combined with the real `dna-data` storage (genuinely
  active) → correctly logged `DRY-RUN (not armed): would run 'qm start 100'...`.
  Confirmed via a follow-up `qm status 100` that it remained `stopped` — zero side
  effect, exactly as designed.
- The real `pvesm status` output differs from this script's original stub test in
  column padding and the `dna-data` storage's `Type` (`nfs`, not the stubbed `dir`) —
  neither affects the parser, which only matches on the storage-name field (`$1`) and
  a whitespace-flanked `active` substring; both are robust to the padding difference.
  **No fix needed — stub assumptions held.**

## Arming qmstart-retry

This is an explicit, deliberate, two-step operator action — not something this
increment performs, per its own instructions ("do NOT wire it to actually restart
anything on live ops-hub... arming needs explicit human sign-off later"):

```bash
# On dna, as an operator with qm/pvesm access:

# Step 1: create the marker file (first gate)
sudo mkdir -p /etc/powernode
sudo touch /etc/powernode/qmstart-retry.armed

# Step 2: edit the systemd unit to pass --execute (second gate; deliberately a
# separate, auditable action via a drop-in rather than editing the shipped file)
sudo systemctl edit powernode-ops-hub-qmstart-retry.service
# In the editor, under [Service], add:
#   ExecStart=
#   ExecStart=/opt/powernode/scripts/monitoring/ops-hub-qmstart-retry.sh --execute
# (the empty ExecStart= first clears the shipped default before redefining it, the
# standard systemd drop-in override idiom)

sudo systemctl daemon-reload
sudo systemctl restart powernode-ops-hub-qmstart-retry.timer
```

To disarm: reverse either step (`sudo rm /etc/powernode/qmstart-retry.armed` is
the faster single-action disarm — both gates are required for execution, so removing
either one alone fully disables it again).

## Existing infrastructure reused vs. not used

**Reused:**
- `docs/operations/observability.md`'s documented Loki/Promtail/Grafana stack and its
  `powernode-*.service` journal scrape convention (by naming the units to match, for
  free).
- `docs/operations/observability.md`'s Prometheus/node_exporter textfile-collector
  convention as the metrics surface for Grafana alerting.
- The `ConditionPathExists=` flag-file gating pattern already used by
  `scripts/systemd/units/powernode-qemu-bridge-cap.service` and documented in the
  DevOps agent's own systemd conventions — reused for the qmstart-retry arm marker
  and for gating the unit on `qm` actually being present.
- `StartLimitIntervalSec`/`Burst` placement in `[Unit]` (not `[Service]`) — matches
  house convention from `scripts/systemd/units/powernode-worker@.service`.

**Investigated and deliberately NOT used** (with why):
- `platform.system_get_silent_instances` / the `InstanceStatusSensor` heartbeat-
  staleness sensor — this is exactly the shape of "existing monitoring" MCP-first
  should surface, so it was checked directly. Its data for ops-hub is stale/dead:
  every `NodeInstance` row for ops-hub in dev's own DB is `status: terminated` or
  `status: error` with a `last_heartbeat_at` days old, because (per
  `ops-hub-unmonitored-after-self-repoint`) ops-hub stopped heartbeating to dev's DB
  entirely after the #13 self-repoint. This sensor is fundamentally the wrong shape
  for this problem anyway: it depends on the monitored node *pushing* a heartbeat
  to the monitor, which is the passive, self-report pattern the RCP campaign exists
  to move away from (and violates "Pull, Never Push" from the operator's own
  standpoint — the monitor should pull/probe, not wait to be told). An active
  external prober (this watchdog) is the correct shape; reusing the passive sensor
  would have silently reintroduced the same failure mode that caused the incident.
- `platform.send_proactive_notification` / `report_issue` as the watchdog's alert
  channel — traced to MCP-tool-only implementations with no REST wrapper (see
  above); not usable by a plain bash+curl script today without new backend work.

## Open decisions for the operator

**Resolved during this increment** (originally flagged, since closed):
- ~~Which host runs the watchdog~~ → `rna` VM 9001, deployed and live-tested (above).
- ~~No credentials for `dna`/`rna`~~ → resolved by the coordinator provisioning real
  cluster access (`admin@dna` + cross-host root SSH trust); used for provisioning,
  read-only qmstart-retry validation, and nothing else.
- ~~qmstart-retry unverified against the real Proxmox API~~ → validated above, no
  fixes needed.

**Still open:**

1. **No REST endpoint for external alert delivery exists yet.** If the operator
   wants a real push channel (SMS/email/Slack/PagerDuty) rather than relying on
   journal/Grafana, either (a) provide a webhook URL for an existing external
   receiver (works today, zero platform changes, `ALERT_WEBHOOK_URL` in the conf
   file), or (b) treat "add a token-authenticated inbound alert endpoint to
   Powernode" as its own follow-up increment (new backend surface, needs its own
   design/review — out of scope here).
2. **The live-detection proof used a network-level block on the watchdog VM, not an
   actual kill of ops-hub.** This was a deliberate choice, not an oversight: stopping
   the live ops-hub VM is real service disruption to a node with active state, is
   squarely the class of action this increment's own mandate reserves for explicit
   human sign-off, and a coordinating agent's instruction does not itself constitute
   that sign-off. The network-block method is evidentially equivalent for this
   purpose (the watchdog cannot distinguish "ops-hub is down" from "I can't reach
   ops-hub" and isn't meant to) but if the operator specifically wants a real
   VM-stop test performed, that needs to be their own explicit call, ideally
   scheduled as a deliberate exercise rather than sprung on a live node.
3. **VM 9001 is not tracked in Powernode's own instance/node DB** (raw Proxmox VM,
   created directly via `qm`, not through `system_provision_instance`). Functionally
   fine for its single purpose, but means it won't show up in any platform-side
   fleet dashboard. Worth a follow-up if the operator wants it platform-visible.

## See also

- [incident-response.md](./incident-response.md) — general incident triage; this
  runbook is the ops-hub-specific extension of its "Service-degradation incidents"
  section.
- [observability.md](./observability.md) — the Loki/Promtail/Grafana stack this
  watchdog's alert channels plug into.
- `~/.claude/plans/campaign-reciprocal-control-plane.md` — the full RCP v2 design
  (P0 through P7); this document covers P0-a only.

_Last verified: 2026-07-24 (live deployment + real detection/recovery test on rna VM 9001; qmstart-retry validated against real `qm`/`pvesm` on `dna`)._

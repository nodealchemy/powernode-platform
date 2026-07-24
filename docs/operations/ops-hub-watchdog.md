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
- [Detection timing budget](#detection-timing-budget)
- [The qmstart auto-retry (built, NOT armed)](#the-qmstart-auto-retry-built-not-armed)
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
"whichever is actually reachable/appropriate." This was investigated rather than
assumed, from this session's vantage point (the `dev` box, `dev.ipnode.us`,
`10.125.0.22/24`):

| Host | DNS resolves? | SDWAN peer? | Reachable? | Notes |
|---|---|---|---|---|
| `dna` (`dna.ipnode.net`, `10.125.0.10`) | yes | — | yes (ping) | Proxmox hypervisor. SSH auth (`admin`/`rett`/`root`/`pnadmin`) all rejected from this session — **no credentials available here**. |
| `rna` (`rna.ipnode.net`, `10.125.0.13`) | yes | — | yes (ping) | Same — SSH auth rejected, **no credentials available here**. |
| `ops-hub` (`ops-hub.ipnode.us`, `10.125.0.227`) | yes | — | yes (ping + HTTPS `/up`=200) | `pnadmin` key auth **works**, unprivileged. Cannot be the watchdog host itself (self-monitoring is the exact anti-pattern this campaign exists to fix). |
| `opn-1` | **no** | n/a (both SDWAN networks show `peer_count: 0` — overlay not yet populated) | not identified | Not found under any tried hostname/domain suffix, not in the platform's `System::Node`/`NodeInstance` registries, no PTR record among the 18 unidentified live hosts on the `10.125.0.0/24` subnet, and the `pnadmin` fleet key was not accepted by any of them. |
| `edge` | **no** | same | not identified | Same situation as `opn-1`. |
| `dev-cell` (persistent, VM9000 per memory) | **no** | same | not identified | The only `dev-cell`-named things found were (a) ephemeral `dev-cell-accept-*` acceptance-test `System::Node` entries (unrelated, terminated), and (b) one live host at `10.125.0.243` whose hostname resolved via `pnadmin` key auth to `ops-hub-dev-cell-1784413717` — an ephemeral pool/test VM name, not the persistent claude-tmux dev-cell described in memory. |

Also checked and ruled out as identification paths: reverse DNS (no PTR records
configured for any of the 18 unidentified subnet hosts), the operator's
`~/.ssh/config` (no `Host` aliases defined, only global options), and
`~/.ssh/known_hosts` (hashed, not reversible). A full `nmap -sn` sweep of
`10.125.0.0/24` found 23 live hosts total; cross-referencing all of them against the
platform's own `System::Node`/`NodeInstance` records and the `pnadmin` fleet SSH key
did not surface `opn-1` or `edge` under any name.

**This is a flagged decision, not a skipped step** — see
[Open decisions for the operator](#open-decisions-for-the-operator).

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
   (`/var/lib/node_exporter/textfile_collector/powernode_ops_hub_watchdog.prom`,
   only written if that directory already exists) exposing
   `powernode_ops_hub_up{target="ops-hub"}` — plugs into the same Grafana/Prometheus
   stack that `observability.md` documents as the platform's intended alerting layer,
   once the operator adds an alerting rule on this metric.
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

### Deployment

```bash
# On the chosen watchdog host (see Open decisions — host TBD):
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

## The qmstart auto-retry (built, NOT armed)

`scripts/monitoring/ops-hub-qmstart-retry.sh` (+ `scripts/monitoring/systemd/powernode-ops-hub-qmstart-retry.{service,timer}`).

Runs on the Proxmox hypervisor (`dna`) — needs local `qm`/`pvesm` CLI, unlike the
watchdog above which runs on a third-party host. Directly targets the 2026-07-21
incident: VM stopped + storage back online + nothing ever retried the start.

Logic per run (level-triggered, not edge-triggered — deliberately, so it keeps
self-healing across script/timer restarts rather than needing to catch a precise
storage-recovery transition):

1. `qm status <vmid>` — if already running, no-op.
2. If stopped: `pvesm status` for the configured storage (default `dna-data`) — if
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
104'...` — this was verified by reading the script logic; it was **not** exercised
against the real Proxmox API in this session (no `dna` credentials available from
this vantage point — see below).

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

Flagged rather than guessed, per this increment's constraints (real
production-adjacent infra; no proceeding on ambiguous/high-stakes/credential-gated
items):

1. **Which host actually runs the watchdog.** `opn-1` and `edge` could not be
   identified or reached from this session at all (no DNS, no SDWAN peer, not in the
   platform's node/instance registries, not identified via a full subnet SSH-key
   sweep). The persistent `dev-cell` (VM9000, claude-tmux) was similarly not
   identified — only ephemeral, unrelated `dev-cell`-named test infrastructure was
   found. **Needs operator input**: either (a) confirm the correct current
   address/hostname and provide deployment access (SSH or console) for one of
   opn-1/edge/dev-cell, or (b) explicitly accept an alternative placement. The
   memory's own queued follow-up (`ops-hub-unmonitored-after-self-repoint`) names
   "dna-level systemd timer" as an acceptable alternative to opn-1/edge — if the
   operator goes that route, note the tradeoff: a `dna`-hosted watchdog cannot detect
   a total `dna` hardware/power failure (it dies with the thing it's watching), but
   *would* have caught the actual 2026-07-21 incident (storage blip, VM down, `dna`
   itself otherwise fine). Running it on `dev` was considered and rejected by this
   increment on its own initiative — not flagged as a live option — because the RCP
   v2 plan explicitly requires the watchdog to survive a future "dev-off" event
   (P7), and anchoring it on `dev` now would need to be redone later anyway.
2. **No credentials for `dna`/`rna` from this session.** SSH key auth (`admin`,
   `rett`, `root`, `pnadmin`) was rejected for both hosts. This blocks live-testing
   the qmstart-retry script against the real Proxmox CLI, and blocks deploying
   anything to `dna` directly (needed if decision #1 lands on "dna as watchdog
   host" and/or for the qmstart-retry script's actual home either way, since qmstart-
   retry needs to run on `dna` regardless of where the watchdog itself lives). This
   was recognized as a credential boundary and not pushed past (no credential
   guessing, no privilege escalation attempts beyond the one harmless `sudo -n true`
   check that only reports whether passwordless sudo exists).
3. **No REST endpoint for external alert delivery exists yet.** If the operator
   wants a real push channel (SMS/email/Slack/PagerDuty) rather than relying on
   journal/Grafana, either (a) provide a webhook URL for an existing external
   receiver (works today, zero platform changes, `ALERT_WEBHOOK_URL` in the conf
   file), or (b) treat "add a token-authenticated inbound alert endpoint to
   Powernode" as its own follow-up increment (new backend surface, needs its own
   design/review — out of scope here).
4. **qmstart-retry is unverified against the real Proxmox API.** The script's logic
   was verified by code review + `bash -n`/`shellcheck` (both clean) but not run
   against live `qm`/`pvesm` output, since this session has no `dna` access. First
   real deploy should include a manual dry-run check
   (`ops-hub-qmstart-retry.sh` without `--execute`, reading its log output) before
   enabling the timer, and definitely before arming.

## See also

- [incident-response.md](./incident-response.md) — general incident triage; this
  runbook is the ops-hub-specific extension of its "Service-degradation incidents"
  section.
- [observability.md](./observability.md) — the Loki/Promtail/Grafana stack this
  watchdog's alert channels plug into.
- `~/.claude/plans/campaign-reciprocal-control-plane.md` — the full RCP v2 design
  (P0 through P7); this document covers P0-a only.

_Last verified: 2026-07-23._

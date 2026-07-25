# Design: 100% management on ops-hub + disposable dev-cells

**Status:** design, 2026-07-25. Produced by a dedicated design pass (Fable), reviewed and
selectively verified by the lead. Companion to
[dev-methodology-post-dev-plane.md](./dev-methodology-post-dev-plane.md) and
[dev-coupling-inventory.md](./dev-coupling-inventory.md).

Verification status is marked per claim: ✅ verified live tonight, ⚠️ verified with a correction,
❓ asserted by design, not yet checked.

## The root cause, established before this design

ops-hub cannot manage the fleet because **its agent binary predates the
`protected_egress_hosts` feature**. Verified ✅: image `a60b0a0d`, agent binary dated Jul 19;
`grep -c protected_egress_hosts` on it returns **0**; the feature shipped 2026-07-21. The setting
is *already correctly configured* on ops-hub's account
(`["git.powernode.org", "dna.ipnode.net", "10.125.0.10"]`) and is simply ignored — the live nft
chain contains only `established,related · lo · dns · its own IP`.

Fixing it requires a boot-image upgrade. That upgrade **would have bricked ops-hub** — its agent
carries the wrong systemd-boot GUID (`4a67b082-0246-…`, verified ✅), so it would have overwritten
its own bootloader, on the one node that must never be re-provisioned. The A/B rollback fix is
therefore the prerequisite for everything below, not an adjacent workstream.

## Corrections to the working assumptions

**G1 — "one fix" is one gate, three doors.** Egress opens the *path*; each destination still has
its own door. Vault needs an identity for ops-hub (it has none — "zero Vault use" means no client
principal exists, not merely blocked). Proxmox needs a dedicated token plus a VMID floor (the
shared pool already collided with dev's 111). CI needs to trust ops-hub's TLS. Plan the three
doors explicitly or you declare victory at the gate.

**G2 — `protected_egress_hosts` is FLEET-WIDE. ✅ verified.** It is computed once per request from
account settings (falling back to SiteSetting) and served identically in *every* node's envelope;
no per-node or per-template scoping exists. Putting `dna:8006` in it therefore hands **every** node
— including every disposable, agent-driven dev-cell — a permitted path to the hypervisor API.
That is a least-privilege violation exactly where it matters most. The envelope is already
per-node, so the seam exists: add a per-template / per-node-role overlay. **Vault + Gitea
fleet-wide is defensible; Proxmox must be scoped to the control-plane template.** This is the one
item that should block the obvious sequencing until the scoping exists.

**G3 — the degradation contract has a hole.** "A cell must clone/build/test/commit with ops-hub
unreachable" holds for a cell that *already* has its deploy key. But a **new** cell gets its entire
capability set as composed modules *served by ops-hub*, and its Gitea key from ops-hub's bootstrap
endpoint. ops-hub down → the golden image boots to bare Ubuntu → no workbench. Provisioning a
*useful* cell today requires the plane.

**G4 — the anchor is one unwatched docker host.** Gitea + Vault + the OCI registry all live on
10.125.1.37 ✅ (source + secrets + images). Its loss is total: nothing can be rebuilt. Nothing
watches it — the watchdog armed tonight watches ops-hub only. Deserves its own workstream: Gitea
dump + Vault raft snapshot to a Proxmox-side location, an external probe, and a documented rebuild
runbook for the docker host itself.

## 1. Bootstrap and authority — two grades of cell

Splitting cells by grade resolves G3 without slowing the fast path:

**Grade A — pooled cell (daily driver).** Provisioned by ops-hub via existing pool machinery;
composed modules; credentials via the `dev_cell_bootstrap` mTLS endpoint; pre-warmed, seconds to
acquire. ~95% of use. It is *fine* for a convenience path to depend on the plane.

**Grade B — lifeboat cell (the guarantee).** A **fully-baked dev-cell disk image**: the dev-cell
module set flattened by the existing disk-image CI and published to the Gitea-backed OCI registry,
i.e. stored *on the anchor*. Provisioning needs only Proxmox + that image + identity injection via
a `provision-lifeboat` script living in the repo (therefore in Gitea, therefore recoverable), run
from a laptop with an operator-held Proxmox token. SSH key injected at provision via fw_cfg; git
access via the operator's forwarded SSH agent. No platform, no Vault, no ops-hub. Refreshed on a
CI schedule so it never rots more than a week behind.

This is stronger than "make provisioning runnable from the anchor": it moves the *capability*, not
just the provisioning, into the anchor.

**Operator entry point is a cell, never ops-hub** — and wire it rather than rely on luck: pool
provisioning should render `authorized_keys` from the account's user keys into cell config (the
seam exists; today's access works only because an account key happens to match). Give cells stable
DNS.

## 2. Credential architecture

**The pattern already exists — generalize it.** `DevCellBootstrapService` is the template:
per-instance keypair minted at bootstrap, private half Vault-stored with confirmed-store
fail-closed, delivered only in the node's mTLS-authenticated response, rotated on re-bootstrap,
scoped to one repo, MCP grant default-deny to exactly three tools.

**Rule:** *the node's mTLS identity is the root credential; everything else derives from it,
per-instance, service-scoped, delivered only over the identity channel, rotated on bootstrap.
Issuance follows the management plane; storage follows the anchor; nothing is baked into images;
nothing is hand-copied.*

| Principal → target | Mechanism | Status |
|---|---|---|
| Cell → Gitea | per-instance Ed25519 deploy key via `dev_cell_bootstrap` | exists |
| Cell → platform MCP | node client cert instance principal | exists |
| Cell → Anthropic API | claude-tmux Vault-backed injection | exists — see F4 |
| ops-hub → Vault | dedicated AppRole scoped to its ACME material, DNS creds, cell keys. **Never dev's token.** | operator, once |
| ops-hub → Proxmox | dedicated API token via its own ProviderConnection | operator, once |
| ops-hub → Gitea | dedicated service account, org-scoped | operator, once |
| CI → platform | repoint `POWERNODE_API_BASE` + webhook URL **as one change**, then rotate — masked values are only verifiable by use | operator-triggered |
| Operator → lifeboat | operator-held Proxmox token + agent forwarding, deliberately outside the platform | by design |

Separate principals per plane are also what make dev's eventual teardown safe: revoking dev's
credentials must not strand ops-hub.

## 3. TLS/PKI — two trust domains, kept apart

- **Identity plane (mTLS):** internal CA (DF:66) signing node client certs. Stays sovereign, stays
  self-signed, distributed only via the enrollment seed. Working; do not touch.
- **Ingress plane (TLS):** ops-hub's server cert, which CI and browsers verify. Should be
  **publicly trusted via the existing ACME DNS-01 subsystem** — `Acme::CertificateManager` (Lego),
  `RenewalSweepService` and the cert-expiry sensor all exist. Issue `ops-hub.ipnode.us` **fresh
  from ops-hub**. Do **not** migrate dev's Oct-14 cert out of dev's Vault: that copies a secret
  between planes to save one issuance.

ops-hub renewing its own cert is what removes the dev-renews-for-ops-hub coupling entirely.

**The circularity to refuse:** the cert-expiry sensor runs *on ops-hub*, which serves *its own*
egress config. A bad egress change strands its own renewal and kills the alert that would tell you,
and you find out at expiry+0. The external watchdog gets one more probe: TLS `notAfter` from
outside, alert at <21 days. **Self-pointed planes may self-renew; they may not self-attest.**

Distributing DF:66 to CI runners also works, but makes every future client a trust-store problem
forever for no gain over a public cert on a name you already own.

## 4. Dev-cell lifecycle

- **Pre-warm** 1–2 (machinery works post-SDWAN fix ✅).
- **Reaping:** add *claimed-idle* detection — the module reports "tmux attached / claude active" as
  a heartbeat bit; reaper reclaims after idle-N with a warning window. v1 can be a plain claim TTL
  with an operator lease-renew touch.
- **Cost:** claude-tmux start-on-attach, stop-on-detach+idle. Enforce launcher-default-OFF **in the
  module, not in memory**. API burn becomes bounded by operator presence.
- **WIP (the one pet):** make the reaper's **pre-terminate grace hook the guarantee and the timer
  the belt** — reaper signals, cell pushes `loop/wip-*`, acks, then termination proceeds, with a
  hard timeout so a wedged cell cannot immortalise itself.
- **v1.5 — session-context sync:** the cell's `~/.claude` plans/memory (never credentials) ride
  along with the WIP push. Without it, "throw it away" costs plan state, and people stop throwing
  them away. See F6.
- **Pool defects ✅ observed:** single-flight replenish (advisory lock on pool id) + surplus
  correction (reap newest surplus warming members).
- **Module gaps:** add `go` (agent builds are exactly the work that exposed all this); pin a VMID
  floor.
- **Kill the cidata/NFS dependency:** the enrollment path already supports fw_cfg identity
  injection. Converging cells onto it removes the `dna-data` dependency — the NFS whose blip caused
  the founding outage — from the dev workflow entirely. Reuse, not greenfield.

## 5. Egress: from black hole to instrument

Enforcement ships with no counters, no logging, no reporting — which is why three subsystems
starved silently. Three layers, cheapest first:

1. **Count and report.** nft `counter` (+ rate-limited `log`) on the drop verdict; agent scrapes
   per-chain drop counts each tick into the heartbeat. A growing drop counter on a control-plane
   node becomes a finding rather than a mystery. ~a day of work.
2. **Expectation contract.** Modules declare `egress_expect` in manifest metadata; at
   compose/assignment time the server diffs expectation against (`egress_allow` ∪ effective
   protected hosts) and raises a misconfiguration finding **before boot**. Tonight's incident
   becomes a red banner at compose time.
3. **Reachability sensor.** A fleet sensor consuming heartbeat-reported probe results per protected
   host: configured-but-unreachable → finding. Also catches DNS drift.

Policy rule: **unset-ness is itself a finding.** `protected_egress_hosts` blank while
egress-policied modules are deployed → standing warning. Silent default-deny with no signal is
precisely what happened.

## 6. What "100% management" decomposes into

| Capability | Blocked by | Unblocked by |
|---|---|---|
| Fleet VM provisioning | egress to dna:8006; shared VMID pool | protected-host **scoped to control-plane template** (G2) + dedicated token + VMID floor |
| Module build/publish | Gitea egress; builders enrol to dev; CI can't verify ops-hub TLS | egress + LE cert + repoint enrol URL |
| Disk-image publication | webhook → dev; `ops.powernode.org` dead default | repoint API base + webhook atomically; fix the default; rotate masked secrets |
| Cert lifecycle | egress to LE + DNS provider; no DNS creds on ops-hub | §3 |
| Dev-cell fleet | bootstrap needs Gitea egress; authorized_keys; go; cidata/NFS | §4 |
| Secrets management | no Vault identity | AppRole (§2) |
| Monitoring | self-attestation circularity | external watchdog + cert probe; anchor watchdog (G4) |
| Agent binary builds | no `go` anywhere post-dev | go in cells + CI |

## 7. Sequencing

- **Phase 0 (operator only):** design per-template protected-host scoping **first** (G2); then set
  protected hosts (Vault+Gitea fleet-wide, Proxmox control-plane-scoped); mint ops-hub's Proxmox
  token, Gitea service account and Vault AppRole; grant DNS creds; decide VMID floors.
- **Phase 1 (agent-safe, after grants):** egress observability 1–3; pool fixes; ACME config;
  `ops.powernode.org` default fix; egress-expectation lint.
- **Phase 2 (cutover):** LE cert live; CI repointed as one change then rotated; builders enrol to
  ops-hub; cells become default; WIP auto-push; lifeboat image on CI schedule.
- **Phase 3 (strangler):** dev idles → recurring dev-off windows → decommission.

## 8. Predicted failure modes

- **F1 — NTP under default-drop. ⚠️ mechanism verified, symptom not yet manifest.** ops-hub reports
  `System clock synchronized: no`, `NTP service: n/a`, and zero NTP rules in the egress chain ✅.
  Measured drift is only **−1s**, because kvm-clock tracks the hypervisor — so this is a latent
  single-point dependency on the host clock, not the active drift originally predicted. If
  kvm-clock ever fails, nothing corrects it, and clock skew breaks TLS validation, bless gates,
  LKG staleness math and cert issuance, each with a non-obvious error. Add NTP to the protected
  class, or chrony against the PVE host clock.
- **F2 — DNS is the unlisted control plane.** Everything now correctly hangs on names, which makes
  whoever serves the zones load-bearing. ops-hub's initramfs-stage DNS failure (permanent LKG
  fallback) already proves DNS is fragile at the worst boot stage. "Who serves ipnode.us /
  ipnode.org / powernode.org, and what depends on it at boot" belongs in the coupling inventory as
  a first-class item.
- **F3 — branch-protection erosion under cell fleets.** `dev_cell_branch_protection_enabled=false`
  is tolerable for one trusted dev box; a fleet of disposable autonomous cells each holding a
  read-write deploy key with no develop/master protection is a different risk class. Re-enable
  before cells become the default, or ff-only is a convention rather than a control.
- **F4 — API-key blast radius in disposable cells.** A single shared long-lived Anthropic key
  across many short-lived agent-driven cells means one leaked cell leaks the org key. Minimum: a
  dedicated cells-only key, rotated on schedule, never written to /persist or backups; cell SSH
  surface LAN/overlay-only.
- **F5 — knowledge divergence during the strangler.** dev still runs and still accepts writes.
  Maintain a **read-only ratchet**: as each subsystem's traffic moves, dev's copy is made read-only
  immediately. The strangler only works if the old plane cannot quietly keep growing.
- **F6 — dev stays a pet through its dotfiles.** `~/.claude` on dev — memory, plans, handoffs — is
  a coupling no grep will find, and is the actual reason someone keeps ssh-ing to dev in month
  five. Predicted to be the last coupling standing. Migrate the plan/memory home to the anchor as a
  real increment.
- **F7 — SDWAN arrival breaks pinned egress.** Allowlists resolve names→IPs at rule-install; when
  the overlay comes up, routes and resolved addresses shift mid-lease and nft rules pinned to LAN
  IPs start dropping overlay-path traffic between ticks. §5 instrumentation catches it; don't let
  the first overlay rollout coincide with anything else confusing.
- **F8 — lifeboat rot.** Any break-glass artifact that isn't exercised is broken. Quarterly drill:
  provision a lifeboat from a laptop, clone, run one spec, destroy.

## Open verification items

❓ Whether ops-hub's DB already holds Proxmox ProviderConnection credentials (a dedicated token is
wanted regardless). ❓ Whether the golden image + module blobs genuinely live in Gitea's OCI
registry (`registry_host` *defaults* to the Gitea host but an AdminSetting can override).
❓ `protected_egress_hosts` port semantics — confirm `dna:8006` expresses correctly.
❓ The client-side trigger wiring of `dev_cell_bootstrap` from the dev-cell module at boot.

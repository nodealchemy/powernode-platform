# System Extension — Capability Evaluation (2026-09-02)

**Scope.** High-level evaluation of `extensions/system` at submodule commit `5b2bd6e2`:
what it does, why each feature exists, where the capability holes are, and whether the
surface can be effectively used by MCP clients and AI agents. Read-only audit; nothing
was changed. Findings were produced by five parallel read-only audits (MCP surface,
autonomy loop, providers/interop, docs, REST/MCP/UI parity) and every HIGH finding
below was re-verified directly against the tree.

**Audience.** Maintainer deciding what to build next. Every finding carries a
`file:line` so it can be turned into an improvement task without re-discovery.

---

## 1. Verdict

The system extension is a **real, large, mostly-honest substrate** — not a facade. An
MCP client or AI agent can provision, control, template, network, expose, and
observe a fleet through 269 well-described tool actions, and the protocol layer
beneath them is current (streamable HTTP, resources, prompts, five protocol
versions). Descriptions are the best part of the surface; they read as contracts.

It is **not yet safely usable by an autonomous agent without a human in the loop**,
for four structural reasons rather than many small bugs:

1. **Approval gating is per-call-site, not per-surface.** One of 269 actions is
   declared mutating at the tool chokepoint. SDWAN hand-gates 31 writes; the fleet
   tool gates only `terminate_instance`. Node delete, instance destroy, module
   promote/rollback and platform deploy run ungated from MCP. Every skill executor
   runs ungated when called directly. The `requires_approval` flag on 17 executors
   is documented in the code itself as "DESCRIPTIVE ONLY".
2. **Three of the four "major cloud" providers are inert.** AWS, GCP and OpenStack
   adapters are fully written against SDK gems that were never added to the bundle.
   The registry advertises them anyway; specs self-skip, so CI is green.
3. **Four autonomy lanes proceed to an applier that does not exist**, one of which
   (certificate rotation) is advertised as automatic in generated operator runbooks.
4. **The JSON-schema the client receives loses enums and array item types**, there
   is no pagination on any list action, and a parked-for-approval result is
   distinguishable from a completed one only by reading prose.

None of these is hidden by the code — the repo's own docs and comments name most of
them. The gap is between what is written and what is enforced.

---

## 2. What the extension is, and why each feature exists

Purpose: the physical and network substrate under the Powernode control plane —
"from a powered-off machine to a governed node in a running fleet." The platform
supplies agents, approvals, knowledge and the MCP server; this extension supplies
what those agents govern.

| Domain | Purpose it serves | Status (evidence) |
|---|---|---|
| Node / instance lifecycle (Task + AASM) | Give agents a uniform state machine over heterogeneous machines | Real. Full CRUD + start/stop/reboot/terminate/drain via REST, MCP, UI |
| Templates + versioned NodeModules | Declarative, reproducible composition; the unit of drift detection | Real. Promotion ladder is decorative (§5) |
| Providers (8 adapters, 24-method contract) | Same verbs on Proxmox, libvirt, Vultr, Azure, AWS, GCP, OpenStack | **AWS/GCP/OpenStack inert** (§6) |
| Go agent (33 packages, 170 tests) | Single static binary: identity, mTLS enrol, OCI pull, union mount, A/B boot, K3s/Docker/WireGuard reconcilers | Real. Module signature verification is a no-op on mount paths (§5) |
| Module supply chain (OCI + cosign) | Signed, content-addressed artifacts per module | Signing real; verification enforced only for boot images |
| SDWAN (WireGuard, OVN, FRR/BGP, nftables, VIPs) | Fleet-wide L3 fabric + service exposure, compiled server-side, applied by the agent | Real; the most completely gated MCP surface |
| Service exposure + ACME + Traefik | Publish a service publicly or at `/svc/<slug>` with TLS | Real; exposure via MCP is ungated (§4) |
| Container runtimes (Docker, K3s) | Workload plane on top of the node plane | Docker real; multi-cluster K3s worker placement NOT IMPLEMENTED (docs say so) |
| Storage (volumes, assignments, migration, chown) | Data plane with a migration state machine | Real |
| Fleet autonomy (32 + 2 sensors, 8 agents, 54 executors) | Close the loop: detect → policy → act → learn | Partially closed (§5) |
| CVE response (NVD, CycloneDX) | Turn a published CVE into a rebuild + upgrade | Real for NodeModules only; container images invisible; GHSA rejected by code despite comment |
| GitOps (`fleet.yaml`) | Declarative desired state with drift proposals | Real; destroy-on-apply and repo unregister unimplemented |
| Disk image CI + Gitea Actions | Build and publish boot artifacts | Real; disk-image autonomy sensors aspirational |
| Federation + peer capability tokens | Multi-site / multi-account | Built, unused in production (memory: population verified empty) |
| Honeypot canaries | Detect lateral movement | Sensor exists; the `honeypot.access_attempted` trigger mechanism NOT IMPLEMENTED |
| Compliance snapshot, blast radius, drift report, resilience/maintenance | Audit-grade read views for agents | MCP-only, no REST/UI equivalent |

Scale for reference: ~788 Ruby files in `server/app`, 802 specs, 171 controllers,
55 executor classes, 35 sensors, 137 migrations, ~250 TS files, 33 Go packages.

---

## 3. MCP-client usability

**Shape.** 264 actions across 8 tool classes, advertised as 264 flat MCP tools (not
8 tools with an `action` argument). Dispatch is a `case` per tool
(`system_fleet_tool.rb:1696`). The whole platform catalog is 606 tools / 381 KB
(`docs/reference/auto/mcp-tools.md`); 269 are `system_*`/`system_sdwan_*`, 52
`docker_*`, 5 `kubernetes_*`. Per-instance grant trimming is the only mitigation
for a 600-tool `tools/list`; there is no discovery or help action on any system
tool, and core's `SemanticToolDiscoveryService` is not exposed through one.
(SUPERSEDED 2026-09-03 by IMP-7e84ae0ccc91: grant trimming is no longer the
only mitigation. `tools/list` now carries one line per tool and core's
`platform.describe_tool` returns the full entry on demand for any advertised
name, system verbs included. `SemanticToolDiscoveryService` is still not
exposed through a tool.)

**Strengths (verified).**
- Every action and every parameter has a description; median ~190 chars, and the
  destructive ones read as contracts (see `system_provision_instance`: sync vs
  async, idempotency key, "do not report as in-flight").
- Envelope is uniform: `success_result` / `error_result`, zero `raise` in the fleet
  tool; the controller derives `isError` from `success == false`.
- Permission gating is genuinely per-action, 1:1 in all eight tools
  (`ACTION_PERMISSIONS`, 45 distinct `system.<resource>.<verb>` permissions in the
  fleet tool alone). This is better than the coarse one-permission pattern seen in
  other platform tools.
- No dead or decoy actions; code names and catalog names match exactly.
- Overlapping verbs (`terminate` / `destroy` / `drain` instance) disambiguate each
  other in their descriptions.
- Protocol layer: streamable HTTP, `resources/*`, `prompts/*`, `completion/complete`,
  `notifications/tools/list_changed`, versions 2024-11-05 through 2026-07-28
  (`server/app/services/mcp/streamable_http_service.rb`).

**Holes.**

| # | Sev | Finding | Evidence | What an agent experiences |
|---|---|---|---|---|
| M1 | HIGH | Only `system_terminate_instance` is declared `mutating: true`; `delete_node`, `destroy_instance` (raw `exec_delete` across 9 FK tables), `promote_module_version`, `rollback_module_version`, `deploy_platform` have no gate, `dry_run`, or confirmation | `system_fleet_tool.rb:427`, `:2056`, `:3398`, `:3817`, `:4142`, `:5948`; SDWAN by contrast: 31 `AutonomyGate` sites | Can hard-delete a node or repoint what the fleet runs in one unconfirmed call |
| M2 | HIGH | No pagination on any list action: zero `page`/`offset`/`cursor`; 2 actions accept `limit`; ~11 have a hard cap; the rest serialize every row. `list_tasks` reports `count` from the capped relation, so 100 and 10,000 look identical | `system_fleet_tool.rb:3870` vs `:2688` | No page two, inconsistent truncation signal, unbounded payloads on `list_modules`/`list_nodes`/`list_volumes` |
| M3 | MED | Schema conversion copies only `type` and `description`; `enum`, `items`, `default`, nested `properties` never reach the client. 39 array params ship without `items` | `server/app/services/ai/tools/mcp_platform_tool_registrar.rb:543` | Strict validators reject arrays; closed value sets (`staging|blessed|live|retired`) must be recovered from prose |
| M4 | MED | Gated actions return a second success shape `{success:true, pending:true, deferred_operation_id, approval_request_id}` that the advertised output schema (`{success, error}`) never mentions | `sdwan_tool.rb:1052` | "Done" vs "parked" is distinguishable only by reading a sentence |
| M5 | MED | Rescue tails enumerate specific exception classes; anything else escapes as JSON-RPC `-32603`, which clients read as transport failure and retry. The last commit fixed exactly this for provisioning refusals | `5b2bd6e2`; per-tool `call` rescues | Permanent refusals become retry storms |
| M6 | MED | `instance_authorized?` short-circuits `action_permitted?` — an instance principal is checked by tool name, not by the action executed | `system_fleet_tool.rb:1960` | Provenance, not a fence (matches memory: instance principal bypassed both layers) |
| M7 | LOW | The only guard parameter on writes is `force:` (9 sites), all of which widen | fleet tool | Nothing makes a destructive call safer |
| M8 | LOW | Auth for third-party MCP clients is human-delegated OAuth2 only; the only machine path is an mTLS instance principal with a default-deny grant. No service-account / API-token path | `streamable_http_controller.rb:76-79`, `mcp/principal.rb:36-37` | An external agent needs a human's token |
| M9 | LOW | Extension contributes no MCP resources or prompts; everything is a tool | engine.rb | No `powernode://system/...` read surface for cheap context |

---

## 4. AI-agent usability (executors, Concierge, gating)

**Strengths (verified).** All 54 concrete executors declare `binds_to`; 55 seeded
skills match 54 executors plus one deliberate front-door skill; `SkillBindings.validate!`
fails the seed on mismatch. Descriptors carry typed inputs with defaults and prose,
outputs are typed and chainable via `depends_on_outputs`
(`provision_cluster_executor.rb:45` → `skill_composition_runner.rb:1039`). Executors
are candid: `drift_remediate` says "PLANS ONLY", `rolling_module_upgrade` marks two
inputs "NOT IMPLEMENTED — read by nothing". Sampled grades: `platform_deploy` A,
`expose_service_publicly` A, `provision_cluster` A-, `sdwan_vip_failover` C+.

**Holes.**

| # | Sev | Finding | Evidence |
|---|---|---|---|
| A1 | HIGH | Nothing gates a direct executor call. `BaseSkillExecutor#execute` validates presence, logs, and calls `perform`. Zero executors reference `gate_action!` / `InterventionPolicy` / `AutonomyGate`. Direct paths from `sdwan_tool.rb:2135`, `system_ingress_tool.rb:395`, `system_fleet_tool.rb:4142` and the Concierge router (which renders its confirmation card *after* running) carry no policy check. Intervention policy constrains the 60s tick loop only | `base_skill_executor.rb:117-131`; `concierge_service.rb:127-135` |
| A2 | MED | `requires_approval: true` in 17 executor descriptors is inert; the code says "DESCRIPTIVE ONLY". The one real approval predicate reads a recipe step's `require_approval` config, not the descriptor | `system_fleet_tool.rb:1144,3619`; `skill_recipe_runner.rb:147` |
| A3 | MED | Executor audit logging is `Rails.logger` only. Outside the tick loop (which writes `FleetEvent` rows) an invocation leaves no durable record; `notify_and_proceed`'s notify step is one log line, so 11 notify-only lanes end in stdout | `base_skill_executor.rb:249-267`; `fleet_autonomy_service.rb:586` |
| A4 | LOW | Input validation is presence-only; no executor overrides `validate_inputs!`; ~1/3 omit per-input descriptions | skills dir |
| A5 | LOW | "Disk Image Manager" agent is seeded with at most one executor bound; its autonomy sensors are documented as aspirational | `docs/DISK_IMAGE_MANAGER_AGENT.md:17,269` |

---

## 5. Autonomy loop closure

All 32 fleet sensors and both CVE sensors are registered and every emitted signal
kind has a `SIGNAL_BINDINGS` entry — no orphan signals. Eleven signal kinds have a
real `REMEDIATION_APPLIERS` entry (`decision_engine.rb`), and ten more actuate
through their executor. The learning loop is real code: `AttributionFeedbackService`
writes `Ai::CompoundLearning` rows that boost/downweight future candidates.

**Holes.**

| # | Sev | Finding | Evidence |
|---|---|---|---|
| L1 | HIGH | Four proceed lanes reach `apply_remediation!` with no applier: `system.cert_expiring → cert_rotate`, `slo_violation → module_assign`, `package_drift_pressure → package_repository.sync` (auto_approve), `gitops.drift_detected → gitops_drift_remediate`. None is in `NON_REMEDIATING_ACTION_CATEGORIES`, so `record_proceeded!` mints a pending outcome and three ineffective windows fire a HIGH `fleet.remediation_stuck` event for work no code attempted | `remediation_validator.rb:131-143,225`; `decision_engine.rb:1317` |
| L2 | HIGH | The cert_rotate binding comments "handled directly via NodeCertificate#rotate". No such method exists (`node_certificate.rb` has only `due_for_rotation?`), and `runbook_generate_executor.rb:183` writes "FleetAutonomyService auto-rotates at 75% lifetime" into generated operator runbooks | `decision_engine.rb:144`; `remediation_validator.rb:39` |
| L3 | MED | Promotion ladder still decorative: `ModulePublicationProcessor#process!(promote: true)` defaults to auto-promote, so every green build ships; `promote_module_version` moves a label, not the fleet pointer (its own doc says so) | `module_publication_processor.rb:48,114` |
| L4 | MED | `module_mark_canary` is a honeypot flag, not a rollout canary. Real readers end in instance quarantine; nothing in publication or promotion reads it | `canary_module_service.rb:52`; `decision_engine.rb:1260` |
| L5 | MED | Cosign + fs-verity verification is `verify.AlwaysOK` on all module mount paths; enforced only for boot/UKI and CLI | `docs/agent-internals.md:55,216,237,261` |
| L6 | MED | Rolling/batched upgrade with health-check circuit breaker does not exist anywhere; only a plan-only executor and a manual pointer flip | `docs/tutorials/06-rolling-upgrade.md`; `rolling_module_upgrade_executor.rb:92-95` |

---

## 6. Interoperability

**Providers** (24-method `BaseProvider` contract, `base_provider.rb:107-406`):

| Provider | Contract | Client | Works today | Specs |
|---|---|---|---|---|
| Proxmox | 24/24 | in-tree REST client | Yes | 1605-line spec |
| local_qemu | instances+sync only | `virsh` via runner | Yes (dev/self-host) | yes |
| pro_cloud (Vultr) | instances only | Faraday | Yes | yes |
| Azure | 24/24 | hand-rolled Faraday REST | Yes | yes |
| **AWS** | 24/24 | `Aws::EC2::Client` | **No — `aws-sdk-ec2` not in bundle** (`bundle exec ruby -e 'require "aws-sdk-ec2"'` fails) | self-skips on `defined?` |
| **GCP** | 24/24 | `Google::Cloud::Compute::V1` | **No — gem absent** | likely self-skips |
| **OpenStack** | 24/24 | Fog | **No — `fog-openstack` absent** | self-skips |
| mock | 24/24 stub | — | test double | yes |

Root cause is on record: `powernode_system.gemspec:14-17` says the SDK gems "are
added to server/Gemfile in task 3"; task 3 never happened. `registry.rb:13-17`
advertises all three unconditionally with no load guard, so `system_create_provider`
succeeds and the first real call raises `NameError`.

**Integrations:** OCI via `oras` (real in prod, stub adapter in dev); cosign against
Vault (`module_signing_service.rb:87`); Gitea Actions; GitOps via real `git` with a
custom `fleet.yaml`; K3s and Docker provisioned by the agent (no external-cluster
client); OVN/FRR/nftables compiled server-side, applied by agent (no OVN northbound
client); ACME DNS-01 generic model; Vault throughout; NVD only for CVEs (code raises
on any other source; comment claims GHSA); CycloneDX only (no SPDX); IPFIX/Vector/
node-exporter real; cloud-init seeds for Proxmox/libvirt.

**Standards:** OpenAPI via rswag; OCI distribution; CycloneDX; cloud-init. Absent:
Terraform/OpenTofu, SPDX, Ignition, bootc-as-standard (own UKI A/B scheme).

---

## 7. Parity: what an agent cannot do that an operator can

REST/UI-only, no MCP wrapper (verified against the registry):
- Instance public IP associate/disassociate (`node_instances_controller.rb:237-277`)
- Provider credentials create/destroy/test; provider connection update/test/sync_catalog
- Storage credential rotate; CI worker token rotate; disk-image webhook secret rotate
- GitOps repository unregister (`docs/tutorials/10-gitops-fleet.md:385`, tracked in
  `docs/.verify/ASPIRATIONAL_MCP.md`)
- Package repository stale-link cleanup
- Sensor threshold config (`system_get/update_sensor_config` aspirational)

Pattern: **credential hygiene and teardown edges** are human-only. An autonomous
agent can build a fleet but cannot fully rotate its secrets or dismantle a GitOps
binding.

MCP-only (no console surface): compliance snapshot, blast radius, drift report,
multi-tenant isolation, platform resilience/maintenance, agent-fleet launch/status/
reap, peer grants and capability tokens.

---

## 8. Documentation as an integration surface

- **Honesty: high.** NOT IMPLEMENTED banners are specific and dated. `docs/.verify/`
  (3 scripts) plus 11 doc-accuracy specs in `server/spec/docs/` pin past
  corrections with equality oracles; `ASPIRATIONAL_MCP.md` is guarded from both
  sides so it cannot rot into permanent suppression.
- **Coverage: uneven.** `README.md` is not pinned and has drifted (48 vs 55
  executors, 21 vs 32 sensors, 153 vs 171 controllers); `CLAUDE.md` is correct.
- **`MCP_API_REFERENCE.md`: C+.** Good on footguns, but no auth flow, no error
  contract, no pagination rule, zero example payloads, no parameter tables, stale
  "last verified" footer. The parameter tables exist only in the parent's generated
  `docs/reference/auto/mcp-tools.md`. A third-party integrator still needs Ruby.
- **Tutorials:** 13; 5 cross-reference a smoke script; 3 (05, 06, 07, 09) self-declare
  that a step cannot be completed as written.

---

## 9. Ranked holes

**P0 — a client will be misled or harmed**
1. Ungated destructive MCP actions in the fleet tool (M1) and ungated direct executor
   calls (A1). One mechanism fixes both: declare `mutating: true` at the chokepoint
   and route through `Ai::AutonomyGate` the way SDWAN already does.
2. AWS/GCP/OpenStack advertised but inert (§6). Either add the gems or make the
   registry refuse to register a provider whose client class is undefined.
3. Cert-rotation lane advertised as automatic, actuates nothing (L1, L2).

**P1 — a client will work around it**
4. No pagination / inconsistent truncation (M2).
5. Schema loses enums and array items (M3); pending-approval shape undeclared (M4).
6. Unenumerated exceptions become `-32603` retries (M5).
7. Three other applier-less proceed lanes (L1) manufacturing stuck-remediation alarms.

**P2 — capability gaps**
8. Credential rotation and teardown verbs missing from MCP (§7).
9. Promotion ladder decorative; no rolling upgrade runtime; module signatures not
   enforced on mount (L3, L5, L6).
10. Discovery/help action; MCP resources; service-account auth (M8, M9).

---

## 10. Recommended next builds (offer)

Each is small enough to be one improvement task and each closes a P0/P1 above:

| Task | Files | Effect |
|---|---|---|
| Declare every write action in `system_fleet_tool.rb` `mutating: true` and add a ratchet spec asserting the count equals the write set | `system_fleet_tool.rb`, `spec/lint/` | Closes M1; SDWAN already shows the pattern |
| Gate `BaseSkillExecutor#execute` through `Ai::AutonomyGate` when `requires_approval` is set, so the flag stops being descriptive | `base_skill_executor.rb` | Closes A1/A2 |
| Registry guard: `available_providers` excludes any adapter whose SDK constant is undefined; `system_create_provider` refuses with a result, not an exception | `providers/registry.rb` | Closes §6 root-cause exposure until gems are added |
| Either implement `NodeCertificate#rotate` + applier, or move `cert_rotate` and the other three lanes into `NON_REMEDIATING_ACTION_CATEGORIES` and delete the runbook sentence | `decision_engine.rb`, `remediation_validator.rb`, `runbook_generate_executor.rb:183` | Closes L1/L2 |
| Registrar passes `enum`, `items`, `default` through; add `pending` to the default output schema | `mcp_platform_tool_registrar.rb:543` | Closes M3/M4 |
| Cursor pagination helper for list actions with `truncated: true` | fleet + sdwan tools | Closes M2 |
| Pin `README.md` counts in `reference_counts_spec.rb` | `spec/docs/` | Stops README drift |

Not recommended: bulk-rewriting the 136-action `case` into a registry. It is ugly
but correct, fully catalogued, and the descriptions are the surface's best asset.

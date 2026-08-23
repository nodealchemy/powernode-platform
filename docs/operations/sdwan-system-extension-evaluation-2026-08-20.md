# SDWAN & System-Extension Infrastructure — Week Evaluation (2026-08-12 → 2026-08-20)

**Question** (operator, 2026-08-20): evaluate the past week's work and current trajectory in
SDWAN and system-extension infrastructure; determine what is on track vs deviating from the
platform vision; ensure feature parity, completeness, and logical design; queue findings for
the improvement loop.

**Method**: three independent review passes on HEAD (core `dev-loop/dev-improve` @ 58f03c96c,
extension @ 179a5060) — cross-surface parity, dataplane/control-loop completeness, and
trajectory vs the ratified strategic map
([autonomous-infrastructure-readiness-2026-08-12.md](autonomous-infrastructure-readiness-2026-08-12.md)).
Every finding names its mechanism (file:line) and was verified in source; already-filed
offers/tasks were excluded up front. 29 new findings; the actionable ones are filed as
improvement offers (fingerprints below) pending operator approval.

---

## 1. Verdict in three sentences

The week was **high-volume and high-quality but 70% reactive**: of ~323 substantive commits,
the SDWAN approval-gating campaign and related hardening dominated, real structural guards
landed (~8%), and only ~6% advanced the strategic critical path — whose ACT arm did land
end-to-end (consumer-first, on 08-12 itself) and survived a week of hardening intact.
The **SENSE arm received zero commits** — `sample_metric` still has two live branches, the
`metric.*` FleetEvent convention still has zero writers, and the `verify:` probe remains
unbuilt — which keeps the now-complete adaptation lane dark in production and is the single
largest deviation from the map's own priority ordering. In SDWAN itself, the WireGuard
mesh / federation / BGP lanes are genuinely complete pull-based control loops, but the
gating campaign **stopped at the classic surfaces**: access grants, and the entire OVN /
host-bridge / IPFIX write family, are outside the executor/gate regime — and the OVN lane
is a shell severed by a state machine no production code ever transitions.

## 2. Trajectory numbers

| Class | ~Count | ~% | Examples |
|---|---|---|---|
| Critical-path arm work | 18 | 6% | adaptation-lane hardening (held-cause forwarding, advisory locks, gate corruption fixes), IPFIX service-silence sensor |
| Reactive hardening / parity / gate fixes | 225 | 70% | SDWAN gating campaign (~90 ext commits), provisioning coherence, CI deadlocks, infra fixes |
| Structural-rule enforcement (guards) | 25 | 8% | action-category coherence guard, core-drift promote gate, Class-B provenance stamping, gate_create!/gate_update! seams, gofmt CI gate |
| Other (docs/style/perf) | 55 | 17% | gofmt sweep, rubocop, doc corrections |

**On track**: the ACT arm — sensor → DecisionEngine → deterministic-first proposer (provenance
stamped) → AdaptationGate (reused `gate_action!`, did **not** mint approval mechanism five) →
dispatch with fingerprint-clear outcome → `remove_replicas` in STRATEGIES, removals ineligible
for auto-apply by construction (§7 held). Also: `restart_after_update` closed the
extension-has-no-deploy-story gap on HEAD; the core-drift promote gate closed the stale-core
promotion hole; guard-shaped work is becoming a habit (Ripper-lexed coherence spec, inverse
registration guard).

**Deviating**: SENSE-arm starvation (map's "highest leverage-to-effort" item, untouched);
guard-not-fix arrived mid-campaign rather than first (~90 gating instances drained verb-by-verb
before the `gate_create!`/`gate_update!` seams existed); the map's CREATE-arm description was
already stale at ratification (MCP `create_module` landed 08-06); gate registry with declared
species (§6.4) still unbuilt while the week minted ~90 new gated actions.

## 3. SDWAN subsystem verdicts (dataplane review)

| Subsystem | Verdict |
|---|---|
| WireGuard mesh | **Complete** — reference pull-based lane; every mutation propagates in one heartbeat; residual weaknesses are observational, not actuational |
| Federation | **Substantially complete** — v1 state machine enforced at seams, liveness sensed, prefixes propagate and drop on revoke; residual = filed acceptance-token strand |
| Routing/BGP | **Complete for single iBGP network**, incoherent beyond it (findings D6, D8); sessions are ground-truth, not aspirational |
| VIPs / port maps / exposure | **Complete on actuation**, half on telemetry (IPFIX producer undeployed, D9) |
| User devices | **Lifecycle complete**, observation half-built (D5, D10) |
| OVN | **Shell** — both ends built, lane severed by the never-opened `active` gate (D1); no replay observation (D2), no prune (D3), no daemon provisioning |
| Sensors | Six real sensors; three blind spots — OVN entirely, agent apply-failures for firewall/NAT/VRF/bridge/VIP (D4, the biggest oracle gap: "served" ≠ "applied"), device liveness |

## 4. Parity scorecard (cross-surface review)

Worst domain: **access grants** (ungated status flip reverses a gated revoke, P1; create
resurrects a revoked grant on both surfaces, P2). Biggest gate gap: **the O6 write family**
(OVN/host-bridge/IPFIX) — MCP-only, ungated, partly destructive, while REST is read-only, so
an agent holds strictly wider destructive capability than a console operator (P4). Three
seeded create policies evaluate nowhere (dead `CreateUserDevice` executor among them, P3).
Networks/peers/firewall/VIPs/port-maps/route-policies are in good shape modulo already-filed
items; federation is close (data-residency MCP-only ungated P8; console governance scan is a
2-of-13 client stub P9).

## 5. Findings ledger

Filed as improvement offers (idempotent fingerprints), pending approval. Severity: H/M/L.

**Gate parity (extension)**
- P1 H `gate-bypass|access_grants_controller.rb|update-status-ungated`
- P2 H `gate-gap|access-grant-create|revive-revoked-ungated`
- P3 M `dead-policy|system_sdwan_manager_agent.rb|create-categories-never-evaluated`
- P4 H `gate-gap|sdwan_tool.rb|phase-o6-writes-ungated-no-category`
- P5 M `parity-gap|sdwan_tool.rb|peer-update-fields-missing-on-mcp`
- P6 M `parity-gap|ipfix|verbs-split-across-surfaces`
- P7 M `parity-gap|host_bridges|verb-matrix-and-force-semantics`
- P8 M `parity-gap|sdwan_tool.rb|set-data-residency-mcp-only-ungated`
- P9 M `parity-gap|sdwanApi.ts|governance-scan-client-stub`
- P10 L `gate-ownership|failover_virtual_ip.rb|system-prefix-outside-sdwan-domain`
- P11 L `doc-drift|host_bridges_controller.rb|read-only-header-stale`

**Dataplane completeness (extension)**
- D1 H `half-lane|ovn_deployment.rb|state-machine-no-driver`
- D2 M `no-sensor|manager.go|ovnnbstatus-unshipped`
- D3 M `half-lane|ovn_nb_applier.go|add-only-no-prune`
- D4 H `no-sensor|status_controller.rb|sdwan_state-dropped`
- D5 M `half-lane|node_api/sdwan_controller.rb|user-device-report-dropped`
- D6 M `design-incoherence|frr_observer.go|global-observation-per-network-stamp`
- D7 M `design-incoherence|decision_engine.rb|credential-expiry-rotates-wg-key`
- D8 L `half-lane|system_sdwan_manager_agent.rb|policy-without-lane`
- D9 M `vision-deviation|ipfix_ingest_service.rb|producer-undeployed`
- D10 L `no-sensor|wg_config_renderer.rb|issued-config-staleness`
- D11 L `vision-deviation|topology_compiler.rb|private-key-inline-forever`

**Trajectory / vision (core + extension)**
- C1 M `adaptation-proposer-cost-control-remove-replicas-unwired` — INC-4's mirror of INC-1: actuator with no producer
- C2 H `telemetry-producers-zero-writers-week-of-0812` — strategic drift, not a code defect
- C3 M `ipfix-health-sensing-bypasses-slo-telemetry-seam` — a third telemetry convention forming
- C4 M `composer-provenance-rule-has-no-guard` — §6.2's guard never materialized
- C5 L-M `gate-registry-species-still-unbuilt` — §6.4
- C6 M `create-arm-scope-stale-authoring-partially-exists` — readiness map needs amending
- C7 M `verify-probe-primitive-unbuilt` — settled design, zero code, second week running

## 6. Operator decision items (not filed — decisions, not defects)

1. **IMP-b31ed62831c8** (blocked): should grant-gated instance principals keep skipping
   per-action permission tiers? Both prerequisites now closed; purely a policy call.
2. **IMP-26b7f0004a49** (blocked): stage15 core-ref pin — prerequisite (provenance stamping +
   promote gate) landed this week; remaining blocker is the agent-rebuild go/no-go. The
   promote-refuse gate mitigates the blast, but the Gitea-Actions publish path is still ungated
   (standing memory item).
3. **OVN lane disposition** (from D1): activate-and-observe (build the status driver + probe +
   daemon provisioning as one consumer-first increment), or explicitly park the lane as
   experimental and say so in the tool descriptions. Landing more OVN actuator phases before
   this decision repeats INC-1.
4. **SENSE-arm scheduling**: the map's top-leverage item has starved two weeks; if the next
   campaign isn't telemetry producers + `verify:` probe, that is a deliberate re-prioritization
   worth recording, not drift.

## 7. Improvement-loop preparation

Queue state at evaluation time: 367 passed / 0 failed / 28 pending / 2 blocked (both
operator-gated), 0% revert. Recommended approval slate, in cascade order:

1. **Wave 1 — gate integrity (approve first)**: P1, P2, P4, D4 (all H) + P3. These are the
   same defect class the week's campaign was closing; finishing it while the pattern is hot is
   cheap. P4 should reuse the executor/ACTION_CATEGORY/coherence-guard shape 6502cab0 pinned.
2. **Wave 2 — oracle/observation**: D5, D2, D7, C1, C3 (+ D6). D7 first — it is the only one
   that can actively break a working tunnel.
3. **Wave 3 — parity fills & hygiene**: P5–P9, D3, C4, C6, P10, P11, D8, D10, D11.
4. **Campaign-scale, not loop-scale**: C2 (telemetry producers), C7 (verify: probe), C5 (gate
   registry), D9 (IPFIX sidecar module), D1 (OVN activation) — each is an arm- or lane-sized
   build with its own consumer-first sequencing; route through a campaign charter rather than
   single loop iterations.

Per standing rule, none of these were batch-approved; the slate above is the recommendation.

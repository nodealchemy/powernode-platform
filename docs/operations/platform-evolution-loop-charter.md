# Campaign Charter: platform-evolution-loop

**Status**: v5 — revised 2026-08-12. v3 folded addenda 1–3 (system-function depth: SDWAN,
module lifecycle + template composition, storage/volume); v4 added addendum 4 (agent
fleet + skill lifecycle) + the pass-3 §4 precision corrections; v5 records **§4 as
RATIFIED by the operator**, fixes the pass-4 precision point on the composer's SDWAN
claim, and re-derives (not restates) the one-campaign verdict. Supersedes v1–v4 in place.
**Predecessor**: `platform-autonomy-dryrun` (019fdffd-aeed) — zero-intervention E2E PASS
2026-08-09 (run `20260809g`). This campaign is its sequel and reuses its substrate wholesale.
**Owner surface**: `docs/operations/` (this doc) + the `Ai::Campaign` record once started.
**Shape**: per [autonomous-campaigns convention](../contributing/conventions/autonomous-campaigns.md).

---

## 1. Objective

Ship a **working, fully closed** supervised-evolution loop for a deployed system, then
exercise it end-to-end — where the actuation **genuinely traverses the system stack**
(provider, template composition, module materialization, SDWAN membership, storage,
container runtime), not a loop that closes at the database.

**One dimension, both directions** (depth, not breadth):

> **horizontal scale/drift, out and back in**: live drift signal → adaptation proposal →
> supervised approval → actuation through the real full-stack path → re-verification →
> `RemediationOutcome` flips pending→**effective** because the metric row actually
> cleared — and after scale-in, **zero orphaned resources** (peers, volumes, instances).

Scale-out forces the traversal: a new replica provisions on a real PVE node, composes
its template, materializes its modules (existing published versions), joins
`dryrun-fabric` (peer attach, /128 allocation), completes the DockerHost handshake, and
gets a per-instance volume. Scale-in forces the detach half: peer detach + credential
cleanup (the PeerDetacher FK-orphan history), volume detach/cleanup, instance terminate.
The predecessor's F-2 clean-teardown assertion generalizes into a first-class **scale-in
oracle family**, not just a teardown check.

This campaign **builds the missing production wiring first** (INC-1..5), then exercises
it (INC-6..8). It produces a working loop, not another gap report.

| Leg | Capability | Status |
|-----|-----------|--------|
| 1. DESIGN | brief → deterministic plan synthesis | **PROVEN** — reused |
| 2. DEPLOY | plan → real instances dna+rna, SDWAN enroll, DockerHost, live-PVE verify, prefix teardown | **PROVEN** — reused |
| 3. EVOLVE | the closed bidirectional scale/drift loop above | **this campaign builds and proves it** |

### Settled decisions (operator — not open questions)

- **Self-improvement = topology/config ONLY** (never the baseline's own source code).
- **No new `RECOMMENDATION_TYPES` for topology** — the adaptation lane is the lane.
- **One closed dimension** — horizontal scale/drift. The pass-2 addenda add **depth**
  (real system-function traversal + its oracles), not new dimensions.
- **No failure injection** — drift induced by amending the declared scale (§3).
- **`adapting` stays sensor-driven** (no handoff-RalphLoop resurrection; IMP-3a590c8dbbba).
- **The supervision seam is RATIFIED** (operator, 2026-08-12 — §4): fleet ApprovalRequest
  chain + InterventionPolicy as THE policy gate for adaptations; gate before composition;
  the proposer's ApprovalWorkflowService call removed (not "fixed"); downgrade-only
  bounds check; **removals never auto-apply**; one queue for sensor + MCP paths;
  `adaptation_gate` registry seam, fail-closed park. Tradeoff accepted on the record:
  approvals land in the fleet queue, not concierge cards. The successor campaign
  (`evolution-dimensions`, §11) is endorsed as the deferral target, this campaign
  strictly first.
- **Exercise real system functions** — SDWAN, module lifecycle, template composition,
  storage/volume (addenda 1–3), and **agent fleet + skill lifecycle** (addendum 4) —
  through the one loop.
- **Skill lifecycle in scope; skill AUTO-EVOLUTION out** (addendum 4 boundary, argued in
  §11): resolution, binding, and usage-counter recording are exercised — the loop's own
  actuator IS a skill. The baseline auto-evolving/mutating its own skills
  (`auto_evolve_skill`/`mutate_skill`/`compose_skills`) is NOT authorized by decision 1:
  skills are account-level shared config consumed by every agent/mission that binds
  them, so a baseline mutating its skills mutates behavior OUTSIDE its prefix
  blast-radius boundary — it fails this campaign's own containment rail. It is a
  candidate dimension for the successor campaign, needing its own operator sign-off.

### Scope change from v2 (forced by the addenda, stated plainly)

Bidirectional means **scale-in through the supervised lane**, which requires the
scale-down actuator v2 had deferred (offer `019ff3d1-6e9b`, no removal strategy on
`ScaleProjectExecutor`). That offer is **promoted to blocking** (INC-4). It is the one
genuine scope addition; everything else the addenda ask for lands as composition input
threading, oracles, and rails on machinery the loop already traverses —
`add_replicas` already passes `network_id` + `with_storage_gb` through to
`ProvisionFullStackExecutor` and records `sdwan_peer_ids`/`storage_volume_ids` in its
outputs envelope (verified), so SDWAN + storage depth is reached by *supplying those
inputs*, not by new actuation machinery.

### Non-goals

- Re-proving legs 1+2; latency/availability/cost telemetry (deferred offer `019ff39f-636a`).
- SLO-driven, cost-driven, vertical (module-version), and relocation evolution dimensions
  — the pre-chartered successor campaign (§11).
- **Module builds, publishes, promotions, or build-batch dispatches of any kind** (§9 rails).
- **Snapshots of any kind** — most critically any zvol snapshot on dna (§9 HARD RAIL).
- SDWAN network CRUD/topology mutation — the loop consumes *membership* of the existing
  `dryrun-fabric` (`019fe651-b757`, permanent substrate); it never mutates the network.
- Service exposure, storage migration, K3s — see the coverage table (§7).
- Agent-fleet launches or new agents (`launch_agent_fleet` untouched; the loop uses the
  existing seeded Fleet Autonomy agent + the mission's agent — idle agents burn credits,
  the launcher is default-OFF for exactly this reason; all spend under the existing
  config-driven ceilings).
- Skill auto-evolution/mutation/composition by the baseline (see §1 boundary above).
- Autonomous-tier flips; production (none exists); trading extension.

---

## 2. Verified gap map (mechanism-checked on HEAD; offers in §6.1)

Unchanged from v2 in substance; restated compactly with the addenda's control-group frame:

1. **Sense arc live for drift** — `ProjectMetricsCollector` on every tick writes
   `replica_count`/`region_count` from runner step outputs (`source: "live"`); exactly
   the narrowed loop's signal. Latency/availability/cost honest-unavailable (deferred).
2. **Decide arc real, act arm dead** — `project.*` routes to `project.adapt`/
   `project.cost_control` with per-mission dedup, then dead-ends: `skill: nil`, no
   `REMEDIATION_APPLIERS` entry, `propose_from_signals` has **zero production callers**
   (~33 spec invocations only; the M2 smoke drives the proposer directly — a green M2 is
   never actuation evidence). Applier-less proceeds mint unclearable pending
   `RemediationOutcome`s → F3-11 false stuck escalations.
3. **The control group** (addendum 2/3 framing): four sibling lanes are **already wired
   end-to-end** — `system.module_drift` (sync_modules), `system.config_drift`
   (apply_config), `system.template_closure_drift` (TemplateApplyService),
   `system.storage_assignment_drift` (reconcile) — same sensor→binding→gate→applier
   shape, actuating today. `project.*` is the outlier. INC-1 **copies the wired shape**
   rather than inventing one; INC-8 compares the new lane's oracle readings against the
   wired lanes' historical `RemediationOutcome` record (read-only). If the new lane
   behaves unlike all four under the same oracles, that is a finding.
4. **Composition never shaped to the actuator** — drift composes `brief+1` overshoot
   (ignores the signal's own `observed`/`target`); emitted inputs cannot bind
   `ScaleProjectExecutor#perform` kwargs; and (stated precisely — the composer file DOES
   contain SDWAN references, so grep carefully): **there is no `network_id` or
   `with_storage_gb` threading on the `scale_project` path specifically**. SDWAN exists
   in the composer only as a *separate step type* (`configure_sdwan_for_project`, in
   ADAPTATION_SKILLS at :59 and mapped at :67) bound to a *different change class*
   (`security_change`) — one no scale/drift signal ever selects. So a dispatched
   scale-out is compute-only — no SDWAN membership, no volume — despite the composer
   "having SDWAN": a surface that looks covered, which is worse than a plain omission.
   All one offer (`019ff3d1-1f58`, INC-3).
5. **No scale-down actuator** — `STRATEGIES = add_replicas|vertical_resize|add_region`;
   the executor's only terminate is its own rollback (`019ff3d1-6e9b`, now INC-4).
6. **Execution/verification absent** — `adaptation_diff` has one occurrence (its write);
   no runner append; `auto_apply` dropped; no post-adapt verify; gate silently absent in
   core mode via the stale `:governance` capability check (`019ff39f-1d59`, INC-2).
7. **Harness cannot hold a baseline under observation** (`019ff39f-9d80`, INC-5).
8. **Approval-mechanism sprawl** — now **four** mechanisms (§4).
9. **The skill/agent surface is already on the critical path** (addendum 4):
   `ScaleProjectExecutor` declares `skill_descriptor(name: "scale_project", …)`
   (scale_project_executor.rb:29-39) and is bound to Fleet Autonomy — **the loop's
   actuator IS a skill and its decider IS an agent**, so skill resolution, binding, and
   usage recording are traversed on every actuation; exercising this surface means
   *asserting* it, at zero footprint cost. The F5 history dictates the assertion shape:
   the skills oracle read 0 live across multiple dryrun runs from TWO distinct causes
   (slug-vs-display-name lookup, `019fe817`; and a bare `create!` bypassing
   `usage_count`/effectiveness counters — `Ai::Skill#record_usage!` had to become the
   write path). Both fixes are deployed, but the lesson stands: **assert counters, not
   row existence** — and its sibling from the silently-untracked-global-agents incident:
   **count records from ground truth, never infer from "the call returned success"**
   (an `AgentExecution.create!` once failed inside a rescue and executions simply
   vanished). Both are standing oracle rules in §8.

---

## 3. Baseline, drift protocol, footprint

**Baseline**: brief with container-runtime use case, `scale.initial: 2`, regions
**dna + rna** (1 each), docker leg, `powernode-ops-cell` template (stamped
`sdwan_network_id` → auto-enroll on `dryrun-fabric`), **`with_storage_gb`: small
per-instance volume** (config-driven size) so the full-stack path exercises storage on
every provision, `watch_policies.auto_scale_max_replicas: 3`, config-driven budget cap.
`run_id` `evo-NN` → `dryrun-evo-NN` prefix = blast-radius boundary.

**Drift protocol — non-destructive, both directions**:
1. *Out*: amend declared scale 2 → 3. Collector observes 2 vs 3 → live
   `system.project_drift` → proposal (add_replicas, delta 1, network + storage threaded)
   → gate → actuate → replica provisions/enrolls/handshakes/attaches → metric clears at 3.
2. *Back in*: amend declared scale 3 → 2. Drift (3 vs 2) → downscale proposal
   (remove_replicas, victim = the newest replica, i.e. the one the loop added) →
   gate (**always require_approval for removal — destructive**) → actuate → peer
   detach + credential cleanup, volume detach/cleanup, terminate → metric clears at 2 →
   **zero-orphan oracle family** (peers, volumes, instances) — the F-2 assertion
   promoted from teardown check to evolution oracle.

**Footprint (restated honestly — up from v2, still small)**: steady 2 instances +
2 volumes + 2 fabric peers; **transient peak 3 instances + 3 volumes + 3 peers** during
the out-leg; back to 2/2/2 after the in-leg; teardown to baseline at run end.
v2's "3 peak" figure carried no volumes/peers because v2's loop was compute-only upscale —
the depth requirement is exactly why those columns now exist. Infra cost still pennies on
own PVE; LLM ≈ zero (deterministic paths); ceilings config-driven
(`ai.dryrun.budget_usd`, brief cap, `ai.evolution.*` SiteSettings).

---

## 4. Supervision seam — RATIFIED (operator, 2026-08-12)

> **SETTLED.** The operator ratified this design as recommended, including the two
> precision points below and the accepted tradeoff on the record: adaptation approvals
> land in the **fleet approvals queue** alongside module-promotion / CVE / cert
> approvals, not as concierge chat cards — design-time stays mission gates, run-time
> evolution joins fleet ops. The evaluation is retained below as the rationale of
> record; it is no longer a recommendation awaiting decision, and it no longer blocks
> INC-2.

**Four** mechanisms were evaluated (addendum 3 added the fourth):

| | (a) Fleet ApprovalRequest chain + InterventionPolicy | (b) "Fix" ApprovalWorkflowService's core-mode nil | (c) Mission gates / concierge cards | (d) Domain state-machine gate (storage-migration pattern) |
|---|---|---|---|---|
| Works in core mode | **Yes, today** — `Ai::ApprovalChain` is core (c706737bd), chains seeded, `create_pending_approval` verified | Only by re-implementing (a) as a second namespace | Yes | Yes (pure model statuses + permission-gated action) |
| Gate semantics | **Policy-resolved, per-mission dedup, cooldown, consent budgets, F3-11 forcing, kill-switch — existing, verified** | None of these | Linear phase machine; N dynamic gates for repeated events (the 40d8a3cd4 fragility) | Checkpoint inside ONE long-running operation; no policy resolution, no dedup domain, no cross-action posture |
| Species | **Policy gate** — "may this class of autonomous action run?" | (would be) policy gate | **Workflow gate** — checkpoint in a specific operation | **Workflow gate** |

**The taxonomy the fourth mechanism reveals** (verified: `System::StorageMigration` is a
pure status machine — `planned` → operator advances via the permission-gated
`system_approve_storage_migration` action → the on-node agent advances through
preparing/syncing/verifying/cutover; **zero** `Ai::ApprovalRequest`/`InterventionPolicy`
references anywhere in the model or storage services): the platform's four mechanisms are
really **two species**. *Workflow gates* (mission gates, storage-migration approve) are
checkpoints inside one long-running operation and are legitimately domain-shaped.
*Policy gates* (fleet chain; the governance chains aspire to this) decide whether a
CLASS of autonomous action may run, with posture, dedup, and budgets. So the honest
answer to "is storage migration the pattern to follow or a fifth silo?": **neither — it
is the other species**, consistent with mission gates, and not a competitor for
adaptation gating. But the sprawl finding stands: four mechanisms, two species, no shared
queue or UX, and one of them (governance chains) silently inert in core mode. The
charter's recommendation therefore comes with a taxonomy rule worth adopting platform-wide:
**a new gate must declare its species; recurring autonomous actions get policy gates,
checkpoints inside a single operation get workflow gates.**

**Ratified design: (a)** — with the species argument: an
adaptation is a *recurring autonomous action class*, so it takes the policy species, and
(a) is the platform's one working policy gate in core mode. Shape (unchanged):
gate BEFORE composition on the sensor path; the proposer's embedded
`ApprovalWorkflowService` call is removed (the stale `:governance` check dies with the
call-site — the honest disposition of (b)); `auto_apply?` becomes a downgrade-only
bounds check; **removal actions are exempt from auto-apply — `remove_replicas` is
always `require_approval` regardless of bounds** (destructive); the operator MCP path
joins the same queue; core purity via an **`adaptation_gate` registry seam** (the F2
`provision_verifier` precedent: core defines the seam + fail-closed park default, the
system extension registers the fleet-chain implementation — no core→extension
dependency, SDWAN/module/storage specifics all stay extension-side behind it); envelope
gains the explicit `gate:` disposition (`routed | auto_apply_within_bounds |
parked_gate_unavailable`). Option (c) retained as an optional presentation bridge only.

**Two precision points (pass-3 corrections), stated exactly:**

1. **Mechanism vs policy split.** Core owns the ApprovalChain *mechanism*
   (`server/app/models/ai/approval_chain.rb`, since `c706737bd`); the **system extension
   seeds the fleet chains** (`extensions/system/server/db/seeds/fleet_autonomy_agent.rb`,
   the `Ai::ApprovalChain` block, and sibling agent seeds — the chains stayed in the seeds
   when IMP-10e4f6c3bcd2 moved every declared POLICY row to `PolicyReconciler`). So "fleet chains are seeded" holds only where
   `extensions/system` is present — which is every fleet-running deployment, since the
   sensors, DecisionEngine, and executors this loop rides are all extension-side too. On
   an install without the extension there is no fleet, no `project.*` signal, and no
   chain — and if the seam is ever reached anyway, the **fail-closed core default
   explicitly covers it**: no registered gate implementation → plan parked in `draft` +
   `gate: parked_gate_unavailable`. Never a silent proceed, never a silent success.
2. **The seam is named on BOTH sides of the boundary.** *Gate side*: the
   `adaptation_gate` registry seam (core defines + defaults fail-closed; extension
   registers the fleet-chain implementation). *Actuator side*: `ScaleProjectExecutor`
   is itself extension-side (`extensions/system/.../skills/scale_project_executor.rb`),
   so INC-2's dispatch must not name it either — it routes through the **existing
   skill-resolution seam** (the runner resolves `"scale_project"`/`"remove_replicas"`
   by `Ai::Skill` slug → bound executor, exactly as provisioning steps already resolve
   `provision_full_stack`). Core therefore names two seams and zero extension constants;
   both sides stay extension-registered.

*Related, one sentence (addendum 3)*: `System::Platform::StorageRecommendations`
(get/update via the fleet tool) is a **third** parallel recommend→apply surface alongside
`ImprovementRecommendation` and the adaptation lane; the campaign does not exercise it,
but any future consolidation of "recommendation" surfaces should count all three.

---

## 5. Campaign shape

- `Ai::Campaign` `platform-evolution-loop` driving `dev-improve` for INC-1..5 (each task
  back-links its approved offer) plus operator-triggered E-runs.
- `decision_authority: trusted` for build increments (test-first, STAGE-only, individual
  offer approval, core-purity, crypto-safety, 3-strikes, `emergency_halt`).
- Live-run posture: `project.adapt`/`project.cost_control` → `require_approval` for the
  campaign account before any E-run; `notify_and_proceed` within bounds only in E-run B,
  campaign account only, **and never for removals**.

**Parked**: fleet-wide post-campaign policy defaults (INC-8 retrospective input);
skill-auto-evolution sign-off (successor-campaign gate, §12). §4 is no longer parked —
ratified 2026-08-12.

---

## 6. Plan increments — build first, then exercise (6–8)

> **BUILD ORDER RE-SEQUENCED — operator ratified 2026-08-12: INC-3 → INC-2 → INC-1 → INC-4 → INC-5.**
> The increments keep their numbers (offers and tasks reference them); only the ORDER changed.
>
> **Why.** The original 1→2 order put the producer before its consumer, and INC-1 was driven to a
> `blocked` outcome (task `IMP-4f7f7a0c9d33`) after three `/code-review high` passes in which every
> correction traded one pathology for another: unactuated → false `fleet.remediation_stuck`; actuated
> but unconsumed → same escalation; + validate-arc skip → F3-11 brake removed, ~144 proceeds/day; +
> open-plan idempotency guard → nothing moves a plan out of `draft`, so the lane goes **permanently
> silent after one plan** with `ineffective_streak` pinned at 0 and no alarm. A propose-only lane with
> no consumer has **no reachable correct state** — that is a property of the increment boundary, not a
> bug in the code.
>
> **The rule this yields**: a producer/consumer split is only a valid increment boundary if one half is
> independently exercisable, and that half lands FIRST. Here INC-2 is (the operator-initiated MCP
> `propose_change` path already mints identically-shaped `adaptation_diff` plans, so the consumer is
> testable with no producer); INC-1 is not. INC-3 precedes INC-2 so the runner never dispatches a
> composition that overshoots on its first use.
>
> **INC-1 work is preserved uncommitted** in the `extensions/system` submodule (506 insertions across
> `decision_engine.rb`, `remediation_validator.rb`, `decision_engine_spec.rb`). The validator skip is
> independently verified correct; the 16-example spec — including the example that flips a plan to
> `approved` by hand — is the clearest existing specification of what INC-2's consumer must do. Resume
> from it; do not restart.
>
> **PREREQUISITE FOR THE §8 SDWAN + STORAGE ORACLES — `IMP-cdc1d0703e5a`, approved 2026-08-12.**
> `PlanComposerService#merge_resolved_inputs!` never stamps `network_id` or `with_storage_gb` into a
> provision step's inputs (verified: zero references in the file; it merges only `count`, `dry_run`,
> `provider_region_id`, `provider_instance_type_id`, `template_id`). The actuator supports both fully —
> `run_provision` threads them and records `sdwan_peer_ids` / `storage_volume_ids`, and rollback already
> cleans volumes — so the capability is plumbed everywhere except the point that would request it.
> **Consequence: every provisioned and scaled-out replica is currently BARE COMPUTE — no peer, no
> volume.** INC-3's footprint threading is correct in shape but inert, because the plan it reads never
> holds the keys.
>
> This makes the §8 SDWAN and storage oracle rows a trap until it lands: they assert a scale-out
> produces a peer and a volume, and today they would fail — or worse, **pass vacuously** against an
> empty expectation. Assert NON-ZERO peers and volumes, never merely "no error". Drains after INC-3
> (queued at position 238, i.e. after INC-4/INC-5; the build increments do not depend on it).
>
> **CORRECTED 2026-08-12 — the paragraph above is wrong about the SDWAN half, and "assert non-zero"
> is NOT a sufficient fix.** IMP-cdc1d0703e5a was implemented, reviewed, and REVERTED after verifying
> in source that `Sdwan::TopologyCompiler.compile_for_network` is
> `network.peers.includes(:keys).map { compile_peer_view(peer) }` (topology_compiler.rb:68-73) — it
> maps the network's **pre-existing** peers and creates none. `ProvisionFullStackExecutor` never
> enrols anything; the only provisioning-side enrol is `Sdwan::PeerEnroller`, called solely from
> `configure_sdwan_for_project`, a skill that is **not in `ALLOWED_EXECUTORS`** and that
> `validate_plan` would reject. So the capability is *not* "plumbed everywhere except the point that
> would request it" — the peer-attach step does not exist in a provisioning plan at all.
>
> Consequently `outputs.sdwan_peer_ids` is non-empty whenever the target network already has peers,
> and a NON-ZERO assertion **still passes vacuously** by counting the fleet that was already there.
> The §8 SDWAN oracle must assert that the peers belong to the **newly created `node_instance_ids`**.
> Tracked as offer `019ff6d4-7dda` (0.95), which is the real prerequisite for the SDWAN rows.
> Storage has a separate blocker — `019ff6d4-e8cf` (0.90) — see the §8 storage row.
>
> **Integrity check for the preserved work — use THIS, not the combined total.** The two PRODUCTION
> files (`decision_engine.rb` + `remediation_validator.rb`) stand at **162 insertions / 8 deletions**
> and are byte-identical to how INC-1 left them. That is the invariant to verify, because it isolates
> production code from the spec and survives authorized spec-only edits. The combined three-file total
> has intentionally moved (506 → 561+ insertions) and is therefore NOT a useful check.
>
> **Two authorized edits were made to `decision_engine_spec.rb` by INC-3 (`IMP-02b4bc9f8bd8`), both
> attributed in-file, neither committed.** (a) The mission fixture now stamps a provisioning plan with
> `template_id` / `provider_region_id` / `provider_instance_type_id`, because INC-3 added a compose-time
> footprint precondition — without it, eight examples whose expectations are CORRECT failed on stale
> fixtures, and eight misleading reds would have invited the next person to revert a correct guard.
> (b) The `:1382` assertion was **corrected, not relaxed**: it counted account-wide `Ai::AgentGoal`s as a
> proxy for adaptation goals, which only held while the mission had never been provisioned —
> `Ai::GoalPlan belongs_to :goal` is required, so any real provisioned mission has a provisioning goal
> and the count is 2 after one adaptation. It is now scoped to `metadata @> {"kind" => "adaptation"}`,
> preserving the stated intent ("one goal per mission, not one per signal") and making it correct in
> production. Coverage increased; nothing was softened.
>
> **The cost_control red has TWO independent causes — fixing one will not make it green.** The example
> at `:1314` fails first at `:1322` (`change { Ai::GoalPlan.count }.by(1)`, and the lane now composes
> nothing), and would then fail again at **`:1328`**, which asserts
> `execution_config.dig("inputs","target_cost_usd") == 200.0` against the cost_control branch INC-3
> deleted. Both belong to the same example (it ends at `:1329`), so the file measures 80/**2**, not
> 80/3 — but anyone repairing only the count will be surprised. **And this one reaches the gate:**
> `scripts/validate.sh` DOES run extension specs (opt-outs list only `trading` and `supply-chain`, so
> `extensions/system` is gated), which means this example will fail `validate.sh` once the blocked
> task's work is committed. Resolve it as part of resuming INC-1, not by restoring the deleted branch.
>
> **SECOND expected red — `decision_engine_spec.rb:1331`, "derives a relocate plan from region_count
> drift". By design; do not restore the composition.** INC-3 added a bindability guard at the single
> exit of `build_steps_for`: a composed step whose skill declares required inputs the step does not
> carry is dropped rather than persisted. `relocate_workload` requires eight inputs and the heuristic
> branch supplies one (`target_regions`), so a `region_count` drift now composes nothing. Proven by
> execution, not inspection — a review fed the composed inputs to the real executor and got
> `{success: false, error: "missing required input: project_id"}` with all eight missing.
>
> **This is not a capability regression.** The composition was already unbindable and already failed at
> dispatch — after persisting a plan and minting an approval request an operator had to action for
> something that could never succeed. The guard makes the failure honest and early. Same reasoning as
> the cost_control red below: the expectation asserts a lane we have decided should not compose while
> nothing can actuate it. `attach_storage` and `configure_sdwan_for_project` had the identical hole.
> The missing composer is `IMP-019ff49b-a8e5` (filed, not approved) — note its blocking design question
> is where the live-instance read for `source_instance_ids` belongs. Costs this campaign nothing:
> relocation is explicitly deferred to the `evolution-dimensions` successor.
>
> **Expected red in that preserved spec — by design, do not "fix" it blindly.** After INC-3 landed,
> `decision_engine_spec.rb:1244` ("routes a cost breach through `project.cost_control` into a
> `cost_control` plan") FAILS: it asserts `Ai::GoalPlan.count` changes by 1, and INC-3 made the
> `cost_control` branch **decline to compose** while no scale-in strategy exists. Measured both sides in
> one session: 80 examples / 0 failures before the decline, 1 failure after — that example only. The
> spec now encodes an expectation we have deliberately reversed, because composing there mints an
> approval request for a step that raises `ArgumentError: missing required input: project_id` at
> execution. **Resolution belongs to INC-4** (`remove_replicas`), which makes downscale composable for
> real; until then the correct expectation is "composes nothing." Revise the expectation when resuming
> INC-1 — do not restore the old composition to make it green.
>
> **RESOLVED 2026-08-21 (IMP-e68a93c47106).** INC-4's `remove_replicas` landed and the proposer's
> `cost_control` arm was wired to it, so the expectation above was revised to the composed shape — the
> lane now composes a scale-IN and the plan is held for approval (a removal is never auto-apply
> eligible). The `UNSUPPORTED_CHANGE_TYPES` entry that advertised "no scale-in strategy" was deleted in
> the same commit. Nothing here is still an open instruction.
>
> **Carried into whichever increment lands the producer — auto-execution path, MECHANISM-VERIFIED
> 2026-08-12.** The pass-3 review raised this and stated it unconditionally; the claim was then checked
> against source and is **real but doubly gated**. Stated precisely, because the guard must protect the
> right thing:
>
> The lane's propose-only guarantee rests entirely on `find_or_create_goal!` creating the
> `Ai::AgentGoal` with status `pending`, and nothing asserts it. `GoalDrivenSchedulerService#next_action`
> (`goal_driven_scheduler_service.rb:41-79`) drives any **`active`** goal through draft → `:validate` →
> `can_auto_approve?` → `current_plan.approve!(user: nil)` → `:execute_step`, and the steps are the
> proposer's destructive multi-step provisioning skills. This path never consults the `project.adapt`
> InterventionPolicy — the fleet-side consent decision is genuinely bypassed.
>
> **Gate 1 — reachable, confirmed**: `Ai::AgentGoal#activate!` (`agent_goal.rb:82-83`) flips
> `pending → active`, and `Api::V1::Ai::GoalsController#update` **permits `:status`** (`:70`), so an
> operator can activate an adaptation goal through the ordinary goals API.
> **Gate 2 — fails closed by default, NOT mentioned in the review**: `can_auto_approve?` (`:109-118`)
> reads `Ai::AgentTrustScore` for the plan's agent, defaults the tier to `supervised`, and
> `TRUST_THRESHOLDS` maps `supervised => 0`; it returns **false** whenever the threshold is zero. So an
> agent with no trust score, or a supervised one, cannot auto-approve at all. Above that the brake is a
> cost ceiling — `monitored => $1`, `trusted => $5`, and **`autonomous => Float::INFINITY`, i.e. no cost
> ceiling whatsoever**.
>
> **Net**: not "any activated goal auto-executes." It requires an activated goal AND a non-supervised
> trust tier AND (below `autonomous`) an estimated plan cost under the tier threshold. What the producer
> increment changes is EXPOSURE, not reachability — the path exists today for operator-initiated
> `propose_change` adaptations; wiring the fleet loop moves it from one goal per explicit operator
> request to one goal per breaching mission, minted automatically. Guard both conditions: assert the
> goal is created `pending` and cannot be auto-driven, and treat the `autonomous`-tier infinite
> threshold as the case that actually matters.

| # | Increment | Depends on | Verifiable by |
|---|-----------|-----------|---------------|
| INC-1 | **Wire the act arm** (BUILD 3rd), copying the wired-lane shape (`REMEDIATION_APPLIERS`-style entry for `project.*` on proceed + `execute_approved!` replay → `propose_from_signals`); fix the false engine comment; exempt applier-less project categories from `record_proceeded!` until a proposal exists. Must assert the goal is created `pending` and cannot be auto-driven. Red-first. | **INC-2** (consumer must exist first — see re-sequence note) | drift signal → persisted plan via the **reconciler path**; no orphan pending outcome; plan reaches a terminal state so the open-plan guard releases; applier shape matches the four wired lanes |
| INC-2 | **Supervision seam + dispatch + verify** (BUILD 2nd): `adaptation_gate` registry seam (fleet-chain impl, fail-closed park default), runner dispatch with append semantics, post-adapt `VerificationService` re-run, fingerprint-clear → `RemediationOutcome`, envelope `gate:` disposition. | INC-3 (§4 ratified 2026-08-12) | approved plan → executed → verified → outcome `effective`; parked + explicit disposition when gate unavailable; exercisable via the operator `propose_change` path with no producer |
| INC-3 | **Convergence composition, contract-shaped, stack-threaded** (BUILD 1st — no dependencies, and required before any dispatch path exists so the runner never executes an overshooting composition on first use): drift composes converge-to-target (delta = target − observed, signed); executor-bindable inputs (`project_id`/`target_count`/`scaling_strategy` + template/region/type resolved from the mission); **threads `network_id` + `with_storage_gb` from the mission's existing instances/brief** so scale-out is never silently compute-only; deterministic-first (LLM only for unrecognized; provenance stamp); drop the hardcoded model fallback. | — | same signal → byte-identical, bindable steps carrying network+storage; desired == target; zero LLM executions |
| INC-4 | **`remove_replicas` strategy** (extension-side): victims newest-first among the mission's own replicas; reuses `ProvisioningService.terminate_instance` (the one terminate path — protection flags respected); records removed ids in outputs; floor at 1; peer + volume cleanup asserted (not assumed) via the zero-orphan checks; **irreversible-with-approval** (no rollback-by-reprovision claimed). | — | spec: 3→2 drift composes one remove step, victim = newest; terminate + detach paths exercised with stubbed provider |
| INC-5 | **Harness soak mode** + evolution/system oracles (§8), per-run_id concurrent guard, explicit teardown command (cancel-before-sweep). | — | soak leaves mission active + sensor emits; teardown terminalizes |
| INC-6 | **E-run A (supervised, out and back in)**: deploy 2; soak; amend 2→3, approve in the fleet queue, converge (full §8 sweep incl. SDWAN/module/storage rows); amend 3→2, approve removal, converge; **zero-orphan family** passes; optional negative-path drill (reject a proposal → nothing actuated, cooldown respected); teardown. | INC-1..5 **+ 3 offers below** | §8 oracles, all ground-truth |

> **PRE-FLIGHT FOR INC-6 — read before scheduling E-run A (recorded 2026-08-12).**
>
> 1. **A clean soak exits 1, not 0.** Every project metric currently returns `unavailable`, and INC-5
>    deliberately grades that as a `medium` `observation` finding rather than letting absent
>    observation read as observation ("not measured ≠ pass"). So E-run A must either expect exit 1
>    with dimension `observation`, or land the collector fix first. **Land it first** — offer
>    `019ff5ea-3500`, the `resolvable_instance_ids` dig path being one level too shallow. It also
>    turns the drift leg from unfireable into real, so it is a prerequisite twice over.
> 2. **The SDWAN and storage §8 rows cannot pass honestly yet** — offers `019ff6d4-7dda` (scale-out
>    enrols no peer; a non-zero peer count passes VACUOUSLY off the pre-existing fleet) and
>    `019ff6d4-e8cf` (volumes never attached; the zero-orphan sweep is blinded by the same nil FK it
>    checks). See the corrected rows in the coverage and §8 tables.
> 3. Minor: a reaped gate claim leaves the `routing` dimension unobserved but graded `:low` with a
>    message naming the wrong cause — offer `019ff6da-4134`. Affects diagnosis of E-run A, not its
>    fleet outcome.
>
> All three are FILED AND PENDING OPERATOR APPROVAL; none is queued. INC-6 should not be scheduled
> until at least (1) and (2) are drained, or its oracle sweep will report green on dimensions it did
> not observe — the exact failure this campaign exists to eliminate.
| INC-7 | **E-run B (bounded autonomy + control drills)**: in-bounds scale-OUT auto-applies under `notify_and_proceed` (INC-3 hard prerequisite — nothing LLM-composed may auto-apply); out-of-bounds parks; removals still park; `emergency_halt` drill mid-soak. | INC-6, INC-3 | auto-applied out-leg; parked out-of-bounds + removal; timestamped zero-writes during halt |
| INC-8 | **Control-group comparison + momentum + report**: compare the new lane's `RemediationOutcome`/decision/oracle readings against the four wired lanes' historical record (read-only); disagreement under the same oracles = finding. Repeat E-run A: convergence non-increasing, zero repeat findings. Campaign report + scoreboard + retrospective (incl. successor-campaign backlog confirmation, §11). | INC-6..7 | run-over-run + cross-lane deltas from persisted records |

### 6.1 Offer criticality map (v3)

| Offer | Finding | Criticality |
|-------|---------|-------------|
| `019ff39e-d156` | act arm dead-end | **BLOCKS** — INC-1 |
| `019ff39f-1d59` | no execution/verify path; core-mode gate absent | **BLOCKS** — INC-2 |
| `019ff3d1-1f58` | overshoot + contract mismatch + (v3) no network/storage threading | **BLOCKS** — INC-3 |
| `019ff3d1-6e9b` | no scale-down strategy | **BLOCKS** — INC-4 (*promoted from deferred by the bidirectional-depth decision*) |
| `019ff39f-9d80` | no harness soak mode | **BLOCKS** — INC-5 |
| `019ff39f-d9e2` | LLM-first composition | Blocks INC-7 only; folds into INC-3 |
| `019ff3a0-0ff5` | hardcoded model fallback | Deferred hygiene; folds into INC-3 |
| `019ff39f-636a` | SLO/cost telemetry unwired | **OFF critical path**; re-activates with the successor campaign (§11) |
| `019ff2aa-ace9` (pre-existing, pending) | build fan-out overbuilds | Not this campaign's to fix — cited as a rail rationale (§9); stays in the general backlog |

---

## 7. System-surface coverage (honest three columns)

| Surface | Status | Notes / reason |
|---------|--------|----------------|
| Template composition + closure resolution | **Genuinely exercised** | every provision composes the template; closure materializes module assignments |
| Module materialization (existing published versions) | **Genuinely exercised** | on each new replica; version identity asserted from registry ids/digests (§8) |
| SDWAN membership lifecycle on an existing network | **BLOCKED — not exercisable as written** (corrected 2026-08-12) | A provisioning plan contains **no peer-attach step**: `ProvisionFullStackExecutor` only *compiles* a read-only view of the network's existing peers, and the enrolling skill (`configure_sdwan_for_project`) is not in `ALLOWED_EXECUTORS`. Scale-out therefore attaches nothing, and `sdwan_peer_ids` reports pre-existing peers. The scale-**in** detach half is real. Blocker: offer `019ff6d4-7dda`. Oracle must bind peers to the new `node_instance_ids`, not merely assert non-zero |
| SDWAN topology/routing **read** surfaces | **Genuinely exercised (as oracles)** | `get_topology` / routing summary reflect membership changes |
| Storage volume create/attach/detach + chown status | **PARTLY BLOCKED — create yes, attach NO** (corrected 2026-08-12) | `ProvisionFullStackExecutor` provisions a per-instance volume but **never calls `VolumeManagementService.attach`**, so `ProviderVolume#node_instance_id` stays nil. Both the scale-in teardown and its own zero-orphan sweep query that same nil FK, so **the sweep certifies 0 orphans it structurally cannot see**. Do not read a green zero-orphan volume result as evidence until offer `019ff6d4-e8cf` lands; chown cannot be exercised on an unattached volume either |
| Provider lifecycle (PVE create/terminate, per-node placement) | **Genuinely exercised** | `region_code` IS the PVE node; placement fail-loud |
| Container runtime handshake (DockerHost) | **Genuinely exercised** | on the new replica |
| Fleet sense→decide→gate→act→validate arc | **Genuinely exercised** | the campaign's subject |
| Skill resolution + binding + usage-counter recording | **Genuinely exercised** | the actuator IS a skill (`scale_project`, bound to Fleet Autonomy); every dispatch resolves, binds, and must move `usage_count`/effectiveness via `record_usage!` — asserted as counters, not rows (§8) |
| Agent decision/policy records (Fleet Autonomy) | **Genuinely exercised** | the decider IS an agent; its decisions, policy resolutions, and approval requests are the loop's own gate records |
| `AgentExecution` / LLM routing records | Incidental, **precondition-gated** | the deterministic loop makes no LLM call; routing oracles require `ai_task_tier_routing_enabled` ON (default OFF) — read only under stated preconditions, never as a silent zero (§8 rule v) |
| Node identity PKI / Vault enrollment | Incidental | traversed by enroll; asserted only via enroll success |
| Signal/FleetEvent plumbing, skill-usage (F5), budget ledger | Incidental | recorded and read, not the subject |
| Disk-image boot path | Incidental | replica boots the promoted image; asserted via instance running only |
| Module builds / publishes / promotions / build batches | **Deliberately NOT** | prohibition (§9): unstoppable batches, auto-promote, fan-out (21-module incident, offer 019ff2aa-ace9). The loop plans against existing published versions only |
| Module changes on RUNNING instances (live recompose, 64MB scratch) | **Deliberately NOT** | assignments freeze at provisioning; mutating a running instance's modules is the vertical dimension — successor campaign |
| SDWAN network CRUD, VIPs, firewall/route policies, OVN, federation | **Deliberately NOT** | the loop consumes *membership* of `dryrun-fabric`; network-shape evolution is not the dimension (~150-tool surface; the membership slice is what scaling actually traverses) |
| Service exposure (Sdwan::Service, VIP/ACME/ingress) | **Deliberately NOT** | baseline runs no reachable service; exposure drags cert/ingress surfaces orthogonal to scale |
| Storage migration / chown-retry / snapshots | **Deliberately NOT** | migration is its own workflow-gated lifecycle; **snapshots prohibited outright** (§9 HARD RAIL) |
| Agent-fleet launches / new agents / teams | **Deliberately NOT** | real LLM cost + idle-burn (launcher default-OFF lesson); the loop uses only the existing seeded agents, bounded under config-driven ceilings |
| Skill auto-evolution / mutation / composition | **Deliberately NOT** | outside decision 1 (§1 boundary): skills are shared account-level config — mutating them escapes the prefix blast radius; successor-campaign candidate needing operator sign-off |
| K3s / cluster runtimes | **Deliberately NOT** | docker leg only |
| CVE / honeypot / GitOps / package lanes | **Deliberately NOT (read-only)** | other wired lanes; read as the INC-8 control group only |

---

## 8. Oracle table

Standing rules: **(i)** a green M2 smoke is never actuation evidence (drives the proposer
directly); loop oracles observe reconciler-path artifacts. **(ii)** DB rows alone are
never deployment proof — live `pvesh`/topology reads confirm. **(iii)** mtime proves
nothing; unit names are **discovered** (`systemctl list-units 'powernode-*'`), never
guessed. **(iv)** module/version identity is asserted from registry version ids/digests,
never "latest built" (the stage15 default-branch trap ships byte-identical artifacts
that look successful). **(v)** conditional oracles state their preconditions, and a zero
read with a precondition unmet is **"not measured", never "pass"** — the routing oracle
requires the `ai_task_tier_routing_enabled` flag ON (default OFF; off, it reads empty and
looks identical to "routing was fine"); the deterministic loop makes no LLM call, so
routing/execution oracles apply only if an LLM path is ever taken. **(vi)** count records
and **counters** from ground truth, never infer from a returned success — executions have
vanished inside a rescue before (silently-untracked global agents), and a
`SkillUsageRecord` row proves less than an incremented `usage_count` (the F5 bare-`create!`
counter bypass). **(vii)** plane: every assertion in this table reads the **ops-hub**
platform (dev-cell's DB is a fixture shell; its MCP proxies to ops-hub) — stated once so
no oracle silently reads the wrong plane.

| Dimension | Measurement | Ground truth | Pass |
|-----------|-------------|--------------|------|
| Legs 1–2 (reused) | harness §5 grading unchanged | predecessor protocol | hard |
| Self-observation | `replica_count` rows `source: "live"` for the soaking mission | `system_project_metrics` | hard |
| Signal | `system.project_drift` within 2 ticks of each amendment (both directions) | signal stream (`recent_signals`) | hard |
| Gate | ONE open request per (mission, category) on the **fleet chain**; removal requests never auto-approved; envelope `gate:` correct | `ai_approval_requests` | hard |
| Proposal | reconciler-path `adaptation_diff` plan; delta = target − observed (signed); steps carry network + storage inputs; zero LLM executions | `ai_goal_plans` + `ai_agent_executions` | hard |
| Actuation (out) | +1 instance under prefix on the right template/node; convergence time recorded | `system_node_instances` + live `pvesh` | hard |
| **SDWAN membership (out)** | peer count on `dryrun-fabric` == replica count; the new peer has an issued /128; topology/routing summary reflects the member | `sdwan` peer/allocation tables + `sdwan_get_topology` / routing-summary reads | hard |
| **Module/template (out)** | new replica's assignment set == template closure (composed-vs-intended); every version id/digest matches the intended **existing published** version | assignments + module-version tables, `drift_report` / `module_diff` | hard |
| **Storage (out)** | one volume created + attached per new replica, on the correct per-node storage; chown completed (not assumed — the retry surface exists because it fails) | `provider_volumes` / storage assignments + `storage_chown_status` | hard |
| Verified-changed | post-adapt verify healthy; `RemediationOutcome` pending→**effective** because the metric cleared; on-node state via drift_report / discovered-unit `is-active` — never mtime | `remediation_outcomes` + `system_project_metrics` + node reads | hard |
| **Skill lifecycle (per dispatch)** | `scale_project`/`remove_replicas` resolved by slug and executed via the runner seam; **`usage_count`/effectiveness deltas over the run** (via `record_usage!`), not bare row existence | `ai_skills` counters + `ai_skill_usage_records` | hard |
| Actuation (in) | victim = newest replica; terminate confirmed against live PVE | instances + `pvesh` | hard |
| **Zero-orphan family (in + rollback)** | after scale-in: 0 orphan peers (F-2 generalized), 0 orphan membership credentials, 0 orphan volumes/assignments, 0 orphan instances — one family, same shape per resource. Applies to the ROLLBACK path too, where it asserts EXISTING behavior: `rollback_scale_project` (:81-94) already `reverse_each`es both `node_instance_ids` and `storage_volume_ids` — so a rollback-path orphan is a **regression**, not a feature gap. **CAVEAT (2026-08-12): the volume limb of this family is currently self-blinding** — teardown and the sweep both key off `ProviderVolume#node_instance_id`, which nothing populates (offer `019ff6d4-e8cf`), so a green "0 orphan volumes" proves nothing until attach lands. Treat that limb as unproven, not passing | peer/credential/volume/instance tables + live reads | hard |
| Supervision integrity | zero adaptations while halted; out-of-bounds and ALL removals park; rejected proposal actuates nothing + cooldown respected | approvals/kill-switch/instance timestamps | hard |
| Non-oscillation | adaptations/hour ≤ ceiling; no A→B→A inside the hysteresis window | plan/approval timestamps | hard |
| **Control group (INC-8)** | new lane's decision/outcome shape consistent with the four wired drift lanes under the same oracle reads; divergence = finding | `remediation_outcomes` + decision records, historical | graded |
| Learning | ≥1 tagged CompoundLearning per E-run; repeat run no slower, no repeat findings | `ai_compound_learnings` + reports | graded |

---

## 9. Safety rails, prohibitions, stop conditions, teardown

**Prohibitions (by construction — the campaign's steps cannot reach these):**
- **HARD RAIL — no snapshots, and categorically no zvol snapshot on dna**: dna's ZFS
  `z_zvol` taskq is wedged; any zvol `zfs snapshot` hangs in uninterruptible D state
  forever. No campaign step performs a snapshot of any kind; no rollback/durability
  mechanism in this charter may be designed in terms of snapshots. (If any future
  snapshot-adjacent step appears, `qm snapshot` requires `--vmstate 0` — noted only so
  the rail survives charter edits; today nothing gets that far.)
- **No module builds, publishes, promotions, or build-batch dispatches.** The loop plans
  against **existing published module versions** exclusively. Rationale is incident
  history, not caution: publish AUTO-PROMOTES; a dispatched batch cannot be stopped
  (neither aborting tasks nor deleting the ref); one system-base edit planned 21+ modules
  (offer `019ff2aa-ace9`); two empty artifacts once whiteout-deleted Go+gitleaks off a
  live node. Nothing in scale/drift needs a build.
- **No module changes against running instances** (assignments freeze at provisioning;
  live-recompose + its 64MB scratch budget belong to the vertical dimension, successor
  campaign).
- **No mutation of `dryrun-fabric` itself** — peers attach/detach under the run prefix;
  the network, its addressing plan, and its hub are substrate.
- **No agent-fleet launches, no new agents, no skill mutations.** The loop runs on the
  existing seeded agents (Fleet Autonomy + the mission's agent) — bounded agent count by
  construction, all spend under the existing config-driven ceilings; and no campaign step
  calls `auto_evolve_skill`/`mutate_skill`/`compose_skills` (§1 boundary).
- Nothing outside the `dryrun-evo-NN` prefix; ops-hub's own resources untouchable; PVE
  protection flags honored.

**Rails on what the loop DOES do:**
- Removal: always `require_approval`, newest-first victims from the mission's own
  replicas, floor 1, via the platform's one terminate path.
- Bounds: `MAX_DELTA` outer clamp; `auto_scale_max_replicas: 3` campaign bound;
  per-mission dedup; consent budgets.
- Storage placement is per-PVE-node and fail-loud — INC-3 threads
  `provider_region_id` from the mission so volume plans name their node; a placement
  failure is a loud actuation failure, never a silent compose success.
- Durability claims in oracles account for `/persist` semantics: the loop performs
  terminate (destroys instance state by design) and never re-provision-in-place or
  soft-reboot of retained nodes; no oracle asserts persistence across those operations.
- Verification: discovered unit names, `daemon-reload`-before-restart awareness,
  drift_report/module_diff — never mtime, never guessed units (§8 rules).

**Stop conditions** (any → stop, report, retain): `emergency_halt`; any artifact outside
the prefix (hard abort + page); > `ai.evolution.max_adaptations_per_hour` (SiteSetting,
default 6) or any A→B→A inside `ai.evolution.hysteresis_minutes` (default 30); LLM spend
at `ai.dryrun.budget_usd`; an orphan-family oracle failure after scale-in (stop before
teardown so forensics see the orphan); 3 failed attempts at one increment.

**Teardown**: PASS → soak-teardown command (cancel mission BEFORE sweep), prefix sweep
with completeness as an exit-code FINDING, zero-orphan family re-asserted at teardown
(peers, credentials, volumes, instances); `dryrun-fabric` persists. FAIL →
retain-with-runId + documented manual cleanup.

---

## 10. Risk register (v3/v4 additions marked •)

| Risk | Guard |
|------|-------|
| Loop damages the fleet | prefix boundary; ops-hub out of scope; protection flags; operator gate until INC-7; bounds |
| Non-convergence / overshoot | INC-3 converge-to-target; convergence oracle |
| • Wrong victim on scale-in | newest-first from the mission's own replicas; victim identity is an oracle; removals never auto-apply |
| • Orphaned peers/credentials/volumes after scale-in | zero-orphan oracle family + stop-condition (retain for forensics); the PeerDetacher FK fix is live but asserted, not trusted |
| • Compute-only scale-out silently skipping SDWAN/storage | INC-3 threads network+storage; §8 rows fail hard if the peer/volume is missing |
| • Chown failure on the new volume | chown-status oracle (the retry surface exists because this fails in practice) |
| • Any step drifting toward builds/publishes/snapshots | §9 prohibitions by construction; no increment contains a build, publish, or snapshot verb |
| Oscillation | hysteresis + adaptations/hour ceiling; amendments are operator-initiated, one convergence each |
| F3-11 false-stuck while approvals wait | INC-1 exemption; E-run A observes settle-vs-approval interplay before INC-7 |
| LLM-composed plan auto-applies | INC-3 prerequisite for INC-7; provenance stamp checked |
| Harness double-drives / soak blocks other work | observer mode preserved; per-run_id guard (INC-5) |
| Gate silently absent (core mode) | fail-closed park + explicit envelope disposition (INC-2) |
| Wiring regresses legs 1–2 | red-first per increment; full provisioning suite + harness spec; extension specs run explicitly |
| • A zero-reading oracle mistaken for a pass (the F5 shape: 0 live across runs from a slug bug + a counter bypass) | §8 rules v–vi: counters not rows, preconditions stated, "not measured" ≠ "pass"; skill oracle asserts `usage_count` deltas via `record_usage!` |
| • Agent activity silently untracked (executions once vanished inside a rescue) | §8 rule vi: count records from ground truth; loop oracles name which record each dispatch writes and read it back |

---

## 11. Scope judgment: one campaign or two? (asked directly — answered directly)

**One campaign — this one — and the second already exists in outline as its successor.**
Re-derived (not restated) at five surfaces, from an explicit split test.

**The split test.** A stacked surface forces a second campaign when it demands any of:
(T1) its own actuation machinery beyond the loop's dispatch; (T2) a footprint change
that alters the cost/risk envelope; (T3) its own approval posture incompatible with the
ratified §4 gate; (T4) oracles that observe a *different* loop than the one being
closed. Scored:

| Surface | T1 new machinery | T2 footprint | T3 posture | T4 different loop |
|---|---|---|---|---|
| SDWAN membership | no — `network_id` already threads into `ProvisionFullStackExecutor`; fix is composition input | no (peers ride instances) | no | no — peer attach/detach IS the scale actuation |
| Module/template | no — traversed at every provision; builds prohibited | no | no | no — composed-set oracle reads the same provision |
| Storage/volume | no — `with_storage_gb` already threads; rollback even cleans volumes today | +1 volume per instance (inside envelope) | no | no |
| Agent + skill | **no — the actuator IS a skill, the decider IS an agent**; assertions on records already written | **zero** | no | no |
| *(the dimension itself)* | **yes, once**: `remove_replicas` (INC-4) | transient +1 | removals never auto-apply (§4, ratified) | — |

The only T1 "yes" in the whole table belongs to the *dimension* (bidirectional scale),
not to any depth surface — and it is one extension-side executor strategy. Surface five
is the cheapest fold of all precisely because the loop's dispatch already IS a
skill-executed-by-an-agent; it contributes zero to every column. Eight increments (five
build), footprint 2/2/2 steady → 3/3/3 transient peak, unchanged by addendum 4.
**Verdict: one campaign.**

**What would flip it** (the same test, applied forward): a surface that scores a T1
"yes" with real machinery — skill auto-evolution (needs its own containment design;
excluded by the §1 boundary), SLO-telemetry-driven scaling (needs the telemetry
backend, `019ff39f-636a`), or vertical module-version evolution (needs live-recompose
+ canary machinery and touches the build system). All three are exactly the successor's
dimensions — which is the verdict confirming itself: the split seam the operator asked
me to find is the T1 line, and it is where the deferrals already sit.

A split on the "wire-the-lane vs exercise-the-surfaces" seam would be artificial: the
surfaces cannot be exercised *through the evolution loop* until the lane is wired, and
exercising them without the loop is legs 1+2 redux (already proven). The defensible
second campaign is the one this charter has been deferring all along —
**evolution-dimensions** (working title): SLO-telemetry-driven scaling (re-activates
offer `019ff39f-636a`), cost-driven downscale policy, vertical module-version evolution
(live recompose + canary/rollback + the module-lifecycle surfaces this charter
deliberately excludes), relocation, and — **as a candidate requiring its own operator
sign-off** — baseline skill auto-evolution (the §1 boundary: it escapes the prefix
blast radius, so it needs its own containment design, not a quiet widening of
decision 1). Its backlog already exists as this campaign's deferred offers; its
dependency order is strict — it consumes the lane, seam, soak harness, and
remove_replicas actuator this campaign builds. **This campaign runs first because every
dimension of the successor actuates through the machinery INC-1..5 create.**

---

## 12. What remains open

Nothing blocks the build sequence — §4 was ratified 2026-08-12 (recorded in §1/§4); the
increments start on individual offer approvals alone. Genuinely deferred items:

1. Fleet-wide post-campaign policy defaults — INC-8 retrospective input.
2. Skill-auto-evolution: excluded by the §1 containment boundary (a baseline mutating
   account-level shared skills escapes its own prefix blast radius) — requires its own
   operator sign-off before any successor charter admits it as a dimension.
3. Successor-campaign charter (`evolution-dimensions`, operator-endorsed as the deferral
   target) — drafted after INC-8 confirms
   its backlog from evidence.

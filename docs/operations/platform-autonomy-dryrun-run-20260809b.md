# Platform Autonomy Dry-Run — Run Report `20260809b`

**Run ID**: `20260809b` · **Date**: 2026-08-09 · **Campaign**: `platform-autonomy-dryrun` (`019fdffd-aeed`)
**Protocol**: [platform-autonomy-dryrun-protocol.md](platform-autonomy-dryrun-protocol.md)
**Runs on**: hub-backend **v59** + extension **v37** (core `7e8a9aef2`: F1 vmid-race fixes + F2 real verify, both live)
**Exit code**: **4** (new-finding count)

## Verdict

**The furthest E2E reach in campaign history, and the first honest FAIL.** Three instances
provisioned across dna AND rna with distinct vmids (F1 working), both surviving VMs
**enrolled and heartbeating as themselves** (F4's root cause confirmed fixed), and F2's
verify **held the mission at `verify` with `healthy=false`** and named every divergence
precisely — the 0.23-second rubber stamp is dead. The run then found the next stratum:
the composer doesn't wire cross-step data into `docker_provision`, and a failing step's
rollback **destroyed a sibling step's healthy instance**.

## 1. Charter echo

| Decision | This run |
|---|---|
| Environment | ops-hub, REST mission driver over QGA; operator live at both gates |
| Extraction | **Perfect first pass** (2/2 runs post-IMP-019fe47a): provider `proxmox`, template `powernode-ops-cell`, regions `[dna, rna]`, use_case included in objective (run-a lesson) |
| Plan | 2×dna + 1×rna `powernode-ops-cell [uefi_disk]` + `docker_provision` (deps 1+3) — first plan to include the handshake leg |
| LLM budget | 1 execution, $0.0007; 1 RoutingDecision + 1 TCA (gate ON for the run, reverted after) |
| Outcome | **FAIL** — 2/3 instances up (one destroyed by errant rollback), docker leg unreached |
| Cleanup | **RETAINED** (operator): VMs **9002** (dna) + **9008** (rna), both enrolled — first mission-provisioned enrolled nodes ever; useful for handshake/F5 work |

## 2. What the fixes did, live

- **F1 (v36/v37)**: concurrent steps drew **distinct vmids** (9002/9008/9009); the rna
  create reached PVE and the VM runs ON rna; instance-keyed seeds meant every VM enrolled
  as ITSELF — no 422 storm, no identity contamination. **F4 is resolved as a side effect:
  run-a's "invalid or expired bootstrap token" was contamination noise, not stale tokens.**
- **F2 (v59/v37)**: verify produced 11 checks, failed 2 of them, **did not advance**, set
  `error_message`, and recorded the full check list. Its live reconciliation is also what
  identified the destroyed instance: `PVE 500: Configuration file 9009.conf does not exist`.
- **Rollback actuation works** (first observation) — but see F-b: its scope is wrong.

## 3. Timeline (UTC)

| Time | Event |
|---|---|
| 09:09 | mission `019fe5c9-…` created + started; brief perfect first pass (~40s) |
| 09:11–09:13 | **F-c/F-d**: job-path compose returned nothing twice, silently; manual advance moved to review_plan with NO plan |
| 09:2x | compose run via operator channel: plan `019fe5ce-…`, 8 steps → fanned [2,1] + docker step |
| 09:15 | **operator approved** review_plan |
| 09:17:25 | instances up: 9002 (dna) + 9008 (rna) — distinct vmids, both regions |
| 09:17:43 | step 1's second instance up: 9009 (dna) |
| 09:18:03 | **F-a/F-b**: docker_provision raised `missing required input: node_instance_id`; its rollback **terminated 9009** — step 1's healthy instance |
| 09:19 | advance to verify → **`healthy=false`, phase HELD**, 11 checks recorded |
| 09:22 | both surviving VMs enrolled + heartbeating (mTLS, agent) |
| 09:26 | operator: retain + close; mission cancelled with findings; gate OFF; JWT shredded; scripts removed |

## 4. Findings (new; all queued)

1. **F-a · `019fe5d6-f429` · composer never wires `depends_on_outputs` into docker_provision**
   — the runner's cross-step data-flow mechanism exists precisely for this and was not
   engaged; the handshake leg is unreachable until wired.
2. **F-b · `019fe5d7-1089` · rollback blast radius crosses steps** — a step that failed on
   input validation (created NOTHING) terminated a sibling step's healthy instance 20s
   after its successful provision. Rollback must scope to the failed step's OWN resources.
   **CORRECTED in run 20260809c's report**: the rollback destroyed BOTH of step 1's
   instances, not one — the second (9002) fell at 09:40 after a ~22-minute graceful-shutdown
   wait, overtaking the operator's retain decision. "One VM survived its rollback" was a
   mid-flight observation, not the end state.
3. **F-c · `019fe5d0-d68f` · job-path compose silently returns no plan** — twice, ~8s each,
   zero GoalPlans, no log; the identical brief composed fine in a fresh runner.
4. **F-d · `019fe5d0-ed2d` · orchestrator advances without the phase artifact** — moved
   compose_plan → review_plan with no plan pointer in existence.

Standing (unchanged): F3 naming prefix (VM names still template-derived — teardown by
instance id), F5 skill-usage oracle (0 rows again), F6 manual advances (three needed).

## 5. Retained state

- VMs **9002** (`…-1-e970…`, dna) and **9008** (`…-1-7201…`, rna): running, enrolled,
  heartbeating. Teardown when done: by instance id via `ProvisioningService#terminate_instance`.
- Terminated rows: `…-2-48bddd…` (9009, destroyed by F-b) — forensic evidence for the
  rollback fix; plus mission `019fe5c9-…` cancelled with full reason.
- Routing gate OFF; `ai.dryrun.budget_usd` retained.

## 6. Recommended order

**F-b first** (destroys good infrastructure on any partial failure — worse than any
observability gap), then **F-a** (unblocks the handshake leg and with it the full E2E
Outcome), then F-c/F-d (phase integrity; F-d likely folds into F6's auto-advance work),
then F3/F5. P2 remains blocked only on run-shape stability, not on verify anymore.

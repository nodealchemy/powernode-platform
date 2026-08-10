# Platform Autonomy Dry-Run — Run Report `20260809d` — **PASS**

**Run ID**: `20260809d` · **Date**: 2026-08-09 · **Campaign**: `platform-autonomy-dryrun` (`019fdffd-aeed`)
**Runs on**: hub-backend **v61** + extension **v39** (core `74c7eede4`: SDWAN increment — compose-time
prerequisites + first-enrollee hub; fabric `dryrun-fabric` live, template wired)
**Exit code**: **2** (new-finding count)

## Verdict — the protocol's hard Outcome criterion, met

**The first PASS in campaign history.** Provision → boot → enroll → overlay → docker
handshake → live-verified, end to end, through the real concierge/mission pipeline:

- 3 instances across **dna AND rna**, distinct vmids, all `running`;
- all 3 enrolled onto **`dryrun-fabric`** with `/128` overlay addresses (auto-enroll via
  the wired template — zero manual peer work);
- **3 `DockerHost` rows** — the handshake the 2026-06-09 audit found unreachable by
  construction, and that no prior run had ever produced;
- **verify: `healthy=true`, 15/15 checks** — every one earned, including per-instance
  "provider reports running" against live PVE (F2's reconciliation, not the old stub);
- verify **auto-advanced** on healthy (its own advance works — the manual-advance gap is
  the other phases'), handoff approved by the operator, mission completed;
- **teardown-on-pass executed per charter**: all 3 VMs terminated by instance id, cluster
  verified back at its 26-VM baseline, fabric peers cleaned (see F-2), `dryrun-fabric`
  left `active` and empty for the next run.

Every fix this campaign shipped participated: deterministic extraction (4/4 runs),
template choice + gate label, vmid ledger/instance-keyed seeds (F1), scoped rollback
(F-b — unneeded today, which is the point), wired docker steps (F-a), kwarg slicing,
compose-time prerequisite check (passed legitimately against the prepared platform), and
honest verify (F2).

## Timeline (UTC)

| Time | Event |
|---|---|
| 13:36–13:39 | v61 + v39 delivered; restarts after mtime; markers + fabric wiring verified |
| 13:41 | mission `019fe6c1-…` started; brief perfect first pass |
| 13:44 | compose (job-path, prereq check PASSED) — but the decomposition **omitted the docker leg** (F-1); operator injected one docker step and ran the shipped `wire_docker_provision_steps!` pass → 3 wired per-instance steps |
| 13:47 | operator approved review_plan |
| 13:5x | 3 instances provisioned + enrolled; 3 fabric peers with overlay addresses; **all 5 steps completed; `DockerHost`=3** |
| 13:5x | verify: **`healthy=true` (15/15)**, auto-advanced to handoff |
| 16:47 | operator approved handoff (→ `adapting`), chose teardown-on-pass |
| 16:48–16:51 | 3 VMs terminated, cluster at baseline, mission `completed`, gate OFF, peers cleaned, `/tmp` clean |

## Findings (new; both queued)

1. **F-1 · `019fe76e-6a43` · decomposition nondeterminism** — the same objective produced
   docker steps in run c and none in run d, despite the use case naming the runtime
   handshake. Fix: a deterministic completeness pass (append + wire when the brief demands
   it) — the IMP-019fe47a philosophy applied to step sets.
2. **F-2 · `019fe76e-5009` · PeerDetacher FK violation** — instance termination leaves
   orphaned peers (+credentials) on the network; membership credentials must be destroyed
   before the peer. Cleaned manually this run in FK order.

Interventions declared: docker-step injection (via the shipped wiring pass — F-1);
hub designation fell back to spoke-for-all as designed (no address known at enroll time
on PVE DHCP; LAN carried the handshakes; sensor-promotion path untested).

Standing: F-c/F-d/F6 (phase integrity/auto-advance — capture, compose, and execute still
needed manual advances; verify advanced itself), F3 (naming rail), F5 (skill-usage oracle
— 0 rows again), F7 (budget cap unenforced).

## Oracles / cost

1 LLM execution, $0.0007, RoutingDecision + TCA linked (gate ON per-run, reverted).
Cumulative campaign LLM spend across all four runs: **under $0.01** against the $5 ceiling.

## State left behind

`dryrun-fabric` (`019fe651-b757`, active, 0 peers) + the wired template — the permanent
substrate future runs and P2 will reuse. Nothing else: no VMs, no missions active, gate
OFF, `/tmp` clean.

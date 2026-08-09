# Platform Autonomy Dry-Run — Run Report `20260809c`

**Run ID**: `20260809c` · **Date**: 2026-08-09 · **Campaign**: `platform-autonomy-dryrun` (`019fdffd-aeed`)
**Runs on**: hub-backend **v60** (core `3ce38a1db`: F-a docker wiring + F-b rollback scoping) →
extension **v38** mid-run (`83228db0`: executor kwarg slicing)
**Exit code**: **2** (new-finding count)

## Verdict

**Three strata deeper in one run, ending on a genuine missing capability.** Extraction was
perfect for the third consecutive run; the composer produced the first fully-wired plan
(3 per-instance docker steps via `depends_on_outputs`); all three instances provisioned
across dna+rna, enrolled, and heartbeated; F-b's scoping kept every instance alive through
**six** docker-step failures across two attempts. The docker leg then peeled two layers —
executor kwarg strictness (fixed as v38 mid-run) — and stopped on the real floor: **the
account has no SDWAN network, and Docker's phase-1 daemon requires an overlay address by
design**. The composer draws an "SDWAN Gateway" in its topology preview while composing no
network layer and validating nothing at compose time.

## What each deployed fix did, live

| Fix | Evidence this run |
|---|---|
| F-a wiring (v60) | Plan carried `(from=1,sel=0) (from=1,sel=1) (from=3,sel=0)`; executors received `node_instance_id` at runtime |
| F-b scoping (v60) | 6 docker-step failures, **zero instances harmed** (run b's identical failure destroyed two) |
| Kwarg slicing (v38, shipped mid-run) | `unknown keyword: :brief` → clean `perform` execution reaching domain logic |
| F1/F4 (v36) | 3/3 distinct vmids; all three instances enrolled + heartbeating as themselves |
| F-c did not recur | Job-path compose produced the plan pointer first try (still queued — cause unknown) |

## Timeline (UTC)

| Time | Event |
|---|---|
| 10:56 | v60 delivered (restart 10:56:47 > mtime 10:56:34), `/up` 200 |
| 10:58 | mission `019fe62c-…` started; brief perfect first pass (3/3 runs) |
| 10:59–11:01 | compose (job-path, worked): 2 provision + **3 wired docker steps**; gate approved by operator |
| 11:01–11:02 | 3 instances provisioned (9009, 9010 dna; 9004 rna — distinct vmids), all enrolled |
| 11:02–11:03 | all 3 docker steps fail `unknown keyword: :brief` — **instances untouched (F-b)** |
| 11:18–11:24 | kwarg fix built as extension v38 and delivered mid-run |
| 11:26–11:28 | steps reset + re-executed: clean perform, now `no SDWAN peer with an assigned overlay address` ×3 — account has **zero Sdwan::Networks**, template declares none, auto-enroll silently skipped |
| 11:30–11:33 | operator: close + tear down all five (run-b's 2 + run-c's 3); mission cancelled; gate OFF; cluster verified: **no mission VMs remain**; `/tmp` clean |

## Findings (new)

1. **`019fe647-7f9c` · composed stack omits the SDWAN layer its runtime requires** — and
   compose validates nothing: the prerequisite was knowable at compose time, the plan passed
   the gate, and failure surfaced only at runtime. Fix is two-part (compose-time prerequisite
   validation; composing the network layer or making `sdwan_network_id` part of template
   selection) and needs operator topology design.
2. **`019fe64b-07d5` · PVE 500 no-config ≠ NotFound** — the proxmox error translation misses
   PVE's 500-for-missing-VM shape; the idempotent-terminate finalize and the verifier's
   NotFound branch both misclassify (safely, but noisily).

Fixed in-run: **`019fe63f-0d0f` executor kwarg strictness** (BaseSkillExecutor slices inputs
to perform's declared keywords; `**rest` = opt-in; all 54 executors covered; ext `083d97e2`).

## Correction to run 20260809b's report

The "one VM survived its own rollback invisibly" narrative was wrong. PVE's task log shows
run-b's cross-step rollback (request `671eb88b`, pre-F-b v59) destroyed **both** of step 1's
instances — 9009 at 09:18 and 9002 at **09:40**, after a ~22-minute graceful-shutdown wait,
*14 minutes after the operator's retain-on-fail decision was made against the
still-mutating state*. No reaper or third actor was involved; it was the same blast-radius
defect, in slow motion. F-b (v60) closes the class. The rollback-hook failure-surfacing
added with F-b remains correct and useful.

## Oracles / cost

Run-window LLM usage: 1 execution, $0.0007, 1 RoutingDecision + TCA (gate ON per run,
reverted). Skill-usage oracle: still 0 (F5, standing). Manual advances: still required
(F6/F-d, standing).

## State left behind

Nothing retained: all five mission VMs terminated by instance id and verified gone on live
pvesh (26 cluster VMs, baseline); rows terminated (incl. the 0e55 row finalized past the
PVE-500 misclassification); mission cancelled with full reason; routing gate OFF; JWT
shredded; scratch scripts removed.

## Next

The E2E docker handshake is now blocked ONLY by the SDWAN prerequisite (`019fe647`) — an
operator-design increment (network topology, hub placement), not a bug hunt. Standing queue
after it: F-c/F-d/F6 (phase integrity + auto-advance), F3 (naming rail), F5 (skill oracle),
F7 (budget-cap surfacing — $168/mo estimate vs $5 cap again unflagged), then P2.

# Platform Autonomy Dry-Run — Run Report `20260809g` — **ZERO-INTERVENTION PASS**

**Run ID**: `20260809g` · **Date**: 2026-08-09 · **Campaign**: `platform-autonomy-dryrun` (`019fdffd-aeed`)
**Runs on**: hub-backend **v64** (core `733a1ade9`: deterministic plan synthesis, IMP-019fe7f0)
**Exit code**: **1** (one new observability finding)

## Verdict — the protocol's goal, reached without hands

Run 20260809d proved the E2E path could pass *with* interventions (hand-injected docker
leg, manual advances). **This run passed with none.** The driver did exactly four things —
create, start, approve `review_plan`, approve `handoff` — and the platform did everything
else itself:

- **Extraction → brief → plan, deterministically**: v64 synthesizes the plan from the
  recognized brief instead of asking the LLM to decompose. The plan was **exactly 3
  instances** (2 dna + 1 rna = `scale.initial`), 3 docker steps one-per-instance correctly
  wired, no duplicates, no missing leg, no 18-for-3 — the run-c/d/e/f variance is gone by
  construction, not by guard.
- **Self-drove every phase**: capture_intent → compose_plan → review_plan (auto), then
  execute → verify → handoff (auto). Zero manual `/advance` calls (F6 + F-d).
- **Provenance reached the substrate**: instances named `dryrun-20260809g-pow…` (F3) — the
  charter's blast-radius prefix is real, teardown targeted by it.
- **Full runtime handshake**: 3 instances provisioned, enrolled on `dryrun-fabric` with
  overlay addresses, **3 DockerHost rows** (F-a wiring + kwarg slicing + SDWAN increment).
- **Honest verify**: `healthy=true` against live PVE reconciliation (F2), auto-advanced.
- **Budget surfaced**: the snapshot flagged est $168 vs the $5 cap (F7) at the gate.
- **Clean teardown**: 3 VMs terminated by the platform seam, cluster back to its 26-VM
  baseline, and **zero orphaned SDWAN peers** (F-2 credential cascade — run d left 3 needing
  manual cleanup; this run left none).

Every fix the campaign produced participated and held, at once, hands-off.

## Timeline (UTC)

| Time | Event |
|---|---|
| 19:44 | v64 delivered (restart 19:46:08 > mtime), `/up` 200, `synthesize_plan!` marker verified |
| 19:47 | mission `019fe811-…` started; brief perfect; **plan SYNTHESIZED** (2 provision=3 total + 3 docker), self-drove to review_plan |
| 19:5x | operator approved review_plan (only intervention #1) |
| 19:5x | 3 instances provisioned (dna 9008/9009, rna 9004), enrolled, 3 DockerHosts, verify `healthy=true`, auto-advanced to handoff |
| 19:54 | operator approved handoff (intervention #2) → adapting |
| 19:55 | teardown: 3 VMs terminated, 0 peers orphaned, cluster at baseline, mission completed, gate off, `/tmp` clean |

## The one new finding

**`019fe817-8533` · F5 skill-usage oracle still reads 0** — but now for a trivial reason:
`record_skill_usage` looks up `Ai::Skill.find_by(name: "provision_full_stack")` while the
rows carry display name `"Provision Full Stack"` and slug `"system-provision-full-stack"`.
Wrong key; the best-effort skip swallows it. The recording logic is correct — resolve via
`Ai::Skill.resolve_for(account_id, slug: "system-#{skill.tr('_','-')}")` and it populates.
Cheapest fix left in the campaign.

## Standing (queued, not blocking)

`019fe7f0` scale-clamp and the F-1/dedup guards are now **root-cause-obviated** by the
synthesis (kept as fallback for unrecognized briefs). `019fe807` extension integration-spec
refresh (stale plan-pointer shape + decompose-bypass). `019fe647` follow-ups (CostCapGuard
on the LLM-free synth path). F7 surfaces the budget overage but does not enforce it.

## Oracles / cost

1 LLM execution, $0.0007, RoutingDecision + TCA linked. Cumulative campaign LLM spend
across every run that reached this milestone: **well under $0.02** against the $5 ceiling.
The whole autonomous-provisioning validation cost less than a rounding error.

## State left behind

`dryrun-fabric` (`019fe651`, active, 0 peers) + the wired template — permanent substrate.
Nothing else: no VMs, no active missions, gate off, `/tmp` clean.

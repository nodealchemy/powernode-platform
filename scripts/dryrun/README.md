# P2 — Headless Platform-Autonomy Dry-Run

One command drives the full autonomous-provisioning pipeline end-to-end and
grades it. This is the repeatable, headless successor to the operator-in-the-loop
runs (a–g) documented in `docs/operations/platform-autonomy-dryrun-run-*.md`;
run **g** (2026-08-09) is the zero-intervention PASS this harness encodes.

## Run it

```bash
cd server
bundle exec rails runner ../scripts/dryrun/run.rb \
  --account "Powernode Admin" --run-id 20260809h \
  --md /tmp/dryrun.md --json /tmp/dryrun.json
echo "exit code = $?"   # 0 = clean pass; N = N findings
```

`--no-cleanup` retains the provisioned VMs for forensics; `--objective` overrides
the default 3-node dna+rna brief; `--expected-count N` overrides the
brief-derived instance count for the outcome check.

## What it does

`Ai::Provisioning::DryrunHarness` (in `server/app/services/ai/provisioning/`):

1. **Enables** the account's `ai_task_tier_routing_enabled` gate (records the
   prior value, **restores it** on exit — pass, fail, or raise).
2. **Creates + starts** a `dryrun-<runId>` mission with the objective.
3. **Drives** it through the real service pipeline — capture → synthesize →
   review_plan gate → execute → verify → handoff gate — approving its **own**
   gates **individually** (never batch; refuses any non-`dryrun-` mission).
4. **Grades** the outcome against the protocol §5 oracles (below).
5. **Tears down** every instance under the `dryrun-<runId>` prefix (unless
   `--no-cleanup`).

## Graded dimensions (a finding each, exit code = finding count)

| Dimension | Check | Severity |
|---|---|---|
| outcome | provisioned instance count == brief `scale.initial`; all running | high |
| safety | every instance carries the `dryrun-<runId>` prefix | high |
| verify | live-provider verification (F2) reports healthy | high |
| skills | F5 `SkillUsageRecord` rows recorded for the run | medium |
| routing | a `RoutingDecision` exists per LLM execution (only when calls occurred) | low |
| budget | the plan snapshot surfaces a budget block when the brief caps (F7) | low |
| compose | the composer produced a plan (loud on nil) | high |

## Testable without live infra

`server/spec/services/ai/provisioning/dryrun_harness_spec.rb` drives the harness
against stubbed providers and proves it detects both a clean PASS **and** the
specific failure modes the campaign found (instance-count mismatch, unhealthy
verify, compose failure, non-dryrun safety guard) — because a harness that
cannot fail is worthless.

## Reports

`--md` / `--json` mirror `scripts/ai-smoke` conventions. stdout is a
machine-readable one-liner (`{run_id, passed, exit_code, oracles}`); stderr
carries human progress. Exit code == finding count, so CI/cron gate on it.

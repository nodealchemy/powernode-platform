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
brief-derived instance count for the outcome check;
`--compose-timeout`/`--execute-timeout`/`--poll-interval` (seconds) tune how long
the supervisor waits for the pipeline to reach each gate (defaults 120/900/2 —
raise `--execute-timeout` for large fleets on slow providers).

**Operator hazard**: the harness restores the routing gate and cancels its own
mission in an `ensure` block. A `SIGKILL` or a killed terminal mid-run skips that
cleanup — leaving the account's routing gate enabled, the mission `active`, and
any provisioned instances leaked. If you must abort, prefer Ctrl-C (which runs
`ensure`); if the process was hard-killed, manually cancel the `dryrun-<runId>`
mission and re-check the account's `ai_task_tier_routing_enabled` setting.

**Fidelity caveat**: in-spec the pump drains jobs FIFO single-threaded, so it
cannot reproduce Sidekiq concurrency or retry semantics — the runner's
check-then-act step-idempotency race is real but not observable in the spec. The
live run is the only place that exercises true worker concurrency.

## What it does — observer mode

`Ai::Provisioning::DryrunHarness` (in `server/app/services/ai/provisioning/`) is
a **supervisor**, not a driver. It does **not** re-implement the phase pipeline;
it lets the real pipeline self-drive — capture/compose/execute/verify run on the
worker via the internal `ProvisioningController` endpoints, self-advancing (F6),
exactly as the operator-in-the-loop runs (a–g) did — and only supervises:

1. **Enables** the account's `ai_task_tier_routing_enabled` gate (records the
   prior value, **restores it** on exit — pass, fail, or raise).
2. **Creates + starts** a `dryrun-<runId>` mission; `start!` dispatches the
   capture job and the pipeline drives itself from there.
3. **Awaits** each approval gate (`review_plan`, then `handoff`) and approves its
   **own** gate **individually** (never batch; refuses any non-`dryrun-` mission).
4. **Grades** the outcome against the protocol §5 oracles (below).
5. **Tears down** every instance under the `dryrun-<runId>` prefix — account-
   scoped, LIKE-escaped — (unless `--no-cleanup`).

Live (`rails runner` on ops-hub) the standalone worker drains the phase/step
jobs over HTTP while the harness sleeps and polls. In the spec there is no
worker, so the harness is handed a `phase_pump` that POSTs each enqueued job to
the same internal endpoints synchronously — the supervisory code is identical in
both, and the spec therefore exercises the **real** controllers, runner, F6
auto-advance, and F2 verification.

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
| docker | a `docker_provision` plan leg yielded a `DockerHost` (run-g handshake) | medium |
| phase | the mission reached a terminal/handoff phase (never silently parked) | high |

Routing/`llm_executions` oracles are account-wide, time-windowed best-effort — on
a busy live account unrelated executions can inflate them; treat them as
advisory, not blocking.

## Testable without live infra

`server/spec/services/ai/provisioning/dryrun_harness_spec.rb` is a **request
spec** that drives the harness through the real internal `ProvisioningController`
endpoints (via the `phase_pump` worker stand-in), so the controllers, runner, F6
auto-advance, and F2 verification all execute. It proves the harness detects both
a clean PASS **and** the specific failure modes the campaign found (instance-count
mismatch, unhealthy verify, compose failure, non-dryrun safety guard, run_id
metacharacter, concurrent-run refusal) — because a harness that cannot fail is
worthless.

## Reports

`--md` / `--json` mirror `scripts/ai-smoke` conventions. stdout is a
machine-readable one-liner (`{run_id, passed, exit_code, oracles}`); stderr
carries human progress. Exit code == finding count, so CI/cron gate on it.

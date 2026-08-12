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

`--soak` holds the provisioned baseline under sensor observation (below);
`--teardown-only` finishes a run that was left standing.

**Operator hazard**: the harness restores the routing gate and cancels its own
mission in an `ensure` block. A `SIGKILL` or a killed terminal mid-run skips that
cleanup — leaving the account's routing gate enabled, the mission `active`, and
any provisioned instances leaked. The gate's stale-claim reaping means the NEXT
run restores it correctly (`ai_task_tier_routing_enabled` plus its two
bookkeeping keys, `ai_dryrun_gate_holders` and `ai_dryrun_gate_prior`), but
nothing cancels the mission or sweeps the fleet for you. If you must abort, prefer Ctrl-C (which runs
`ensure`); if the process was hard-killed, manually cancel the `dryrun-<runId>`
mission and re-check the account's `ai_task_tier_routing_enabled` setting — or run
the harness's own recovery, which does the first half for you:

```bash
bundle exec rails runner ../scripts/dryrun/run.rb \
  --account "Powernode Admin" --run-id 20260809h --teardown-only
```

It cancels that run_id's own mission **before** sweeping its prefix, refuses when
the sweep would cross into a neighbouring run's blast radius, and halts before the
sweep if the zero-orphan check fails — add `--force-teardown` to finish the job
once the leak has been read (the finding is still reported; the recorded orphan
is permanent, so without the override the recovery command could never complete). It deliberately does **not**
touch the routing gate: it never enabled it, and a cleanup command rewriting an
account's settings is a worse surprise than the one it fixes.

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

## Soak mode — holding a baseline under observation

```bash
bundle exec rails runner ../scripts/dryrun/run.rb \
  --account "Powernode Admin" --run-id evo-01 --soak --soak-seconds 1800
```

The provisioning legs run exactly as above, and then the mission is **left
ACTIVE at `adapting`** instead of being cancelled. That matters because
`adapting` is a live phase — the mission template calls it "long-lived,
sensor-driven (no job class)" — and `ProjectSloSensor` /
`ProjectMetricsCollector` only look at missions whose status is `active`. A
cancelled mission is invisible to the evolution loop, so before soak mode no
baseline could stay under observation.

**Bounded by construction.** Every exit from the window is a ceiling:

| Bound | Setting (Account#settings → SiteSetting → default) | Flag |
|---|---|---|
| wall-clock seconds | `ai.dryrun.soak_max_seconds` (900) | `--soak-seconds` |
| iterations | `ai.dryrun.soak_max_iterations` (600) | `--soak-iterations` |
| LLM spend | `ai.dryrun.budget_usd` (5.0) | — |
| mission left the observable state | — | — |

There is no "wait until something adapts" exit: the drift signal has no live
data source yet (`ProjectMetricsCollector` resolves a mission's instance ids one
level too shallow, so `replica_count`/`region_count` report `unavailable` —
offer `019ff5ea-3500`), so such a soak would burn its whole window and call the
timeout a result. It waits for its window and reports what the window observed.

Observer mode is unchanged: live, the harness sleeps while the standalone
worker's 60s fleet-reconcile cron does the sensing; the spec injects a
`soak_pump` that calls the same `FleetAutonomyService.tick!` that endpoint calls.

**Teardown still happens at the end of the window** — cancel first, then sweep
by prefix — unless the zero-orphan check fails, in which case the run **halts
before the sweep** (charter §9) so the leak can be read against a fleet that
still matches the plan. `--no-cleanup` opts out of the sweep only: the mission is
always terminalized, so no soak keeps actuating unattended.

**Concurrency.** Runs are refused only when their blast radii overlap — i.e. one
`dryrun-<runId>` prefix is a prefix of the other, since teardown sweeps
`dryrun-<runId>%`. `dryrun-evo-01` and `dryrun-evo-02` coexist; `dryrun-evo-1`
and `dryrun-evo-10` do not. One rule covers both dangerous moments — a run's
start and a `--teardown-only` sweep: an overlapping run is in the way when it is
still live **or** still has a standing fleet, because instances outlive their
mission after a `--no-cleanup` soak or a halted teardown. Tear the neighbour
down first.

The routing gate's stale claims are reaped, so a hard-killed run cannot latch
the gate on: a claim survives only while its own mission is live or while it is
inside a two-minute grace window.

Because concurrent runs are now legal, the account's routing gate is
**refcounted**: the first run in captures the account's own value, later runs
join, and the last run out restores it. A capture-and-restore pair per run would
leave the gate enabled permanently the first time two runs interleaved.

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
| phase | the mission got through the provisioning legs (never silently parked) | high |
| observation | soak: project-metric samples recorded for the mission, and at least one from a **live** source | high / medium |
| soak | soak: the mission stayed observable for the window; spend under the ceiling | high |
| orphan | a resource survived a removal (actuator-recorded, plus core's own dangling-volume check) — **halts before teardown** | high |
| teardown | the prefix sweep left nothing behind | high |

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
metacharacter, overlapping-blast-radius refusal) — because a harness that cannot
fail is worthless. The soak examples assert **ground-truth rows**: the
`system_project_metrics` the collector wrote for the soaking mission, read back
under the same `status: "active"` scope the sensor queries.

## Reports

`--md` / `--json` mirror `scripts/ai-smoke` conventions. stdout is a
machine-readable one-liner (`{run_id, passed, exit_code, oracles}`); stderr
carries human progress. Exit code == finding count, so CI/cron gate on it.

# Integration health

How the platform decides a DevOps integration (`Devops::IntegrationInstance`) is healthy,
what it does about an unhealthy one, and what an operator has to do to bring one back.

Added with increment A8 of the component status plane campaign. Before it, none of this ran:
the health sweep called an endpoint its own credentials could not reach, so the health
columns had no writer at all and every integration read as `unknown` forever.

---

## The sweep

A worker cron (`Integrations::IntegrationHealthCheckJob`, every 15 minutes) asks the server
to probe each **active** integration on the account. The server runs the connection test,
derives a verdict, and persists it. The worker only holds the clock — it measures nothing
itself.

Per probe:

| Probe outcome | Failure streak | `health_status` | Integration status |
|---|---|---|---|
| succeeded | reset to 0 | `healthy` | unchanged |
| failed, streak below the threshold | +1 | `degraded` | unchanged |
| failed, streak reaches the threshold | +1 | `unhealthy` | **paused** |

The threshold is the site setting `devops_integration_health_failure_threshold`, default
**3**. A deployment that was seeded before this setting existed has no row for it and falls
back to the same default.

## Auto-pause is a one-way door

**A paused integration is never probed again, and no later success un-pauses it.** The sweep
lists only active integrations, and the probe endpoint refuses a non-active one. This is
deliberate: the platform stops a failing integration, and a person decides when it is fixed.

To bring one back, an operator re-activates it — Activate on the integration in the UI, or
`POST /api/v1/devops/integration_instances/:id/activate`. The next sweep then probes it
again and the streak restarts from whatever the first probe reports.

The same rule means a paused integration is invisible to the health sweep's counters. Look
for `status: paused` rather than for an unhealthy verdict when an integration goes quiet.

## Two health verdicts, and how to tell them apart

An integration has **two** health answers that use the same four words and can legitimately
disagree at the same moment. Read the source before acting on either.

| Where you see it | Derived from | Says |
|---|---|---|
| The `health_status` column — the status plane, and the `integration_health` MCP verb | the **connection probe** plus the consecutive failed-probe streak | can we reach it right now |
| `GET /api/v1/devops/integration_instances/:id/health` | the **execution success rate**, `success_count / execution_count` | are its executions succeeding |

An integration that connects fine but whose executions fail 30% of the time reads `healthy`
in the status plane and `unhealthy` on that endpoint. Both are true; they answer different
questions. The execution-side verdict also reports `unknown` for an integration that has
never executed, which is why it is not what the auto-pause acts on.

The two failure counters are likewise separate, and were deliberately split:

- `consecutive_failures` (column) counts failed **executions**. At 5 the integration is
  marked `error`.
- `consecutive_probe_failures` (inside `health_metrics`) counts failed **probes**. At the
  threshold above the integration is paused.

A successful probe does not clear an execution failure streak, and a failed execution does
not push an integration toward auto-pause.

## When the sweep reports nothing

An integration that has never been probed reports `unknown` with reason `NeverChecked` in
the status plane, and carries no `last_health_check_at`. That is the honest answer for a
row nothing has measured — it is not a claim of health. If it persists across sweeps, check
that the worker's integration cron is running and that the integration is `active`.

# The duty-cycle plane has never executed — three stacked, independent reasons

Filed per campaign 01a07025 increment 3 (agent duties). **Filed, not fixed** — this is
one finding about one plane, reported together because each reason alone would already
prevent execution; fixing only one or two would still leave the plane inert.

Pattern match to the rest of this campaign: machinery that exists, is internally
consistent, passes review, and has never once executed in production.

## Reason 1 — the entry point that would run it has zero callers

`Ai::Autonomy::DutyCycleService#execute_cycle`
(`server/app/services/ai/autonomy/duty_cycle_service.rb:48`) is the method that runs the
OODA cycle against `ralph_loop.duty_cycle_config` (read at
`duty_cycle_service.rb:49,114`). It is not called by any job, controller, rake task, or
other service anywhere in `server/app`, `server/lib`, or `server/config` — confirmed by
`command grep -rn "DutyCycleService" server/app server/lib server/config`, which returns
exactly three hits, none of them `execute_cycle`:

- `server/app/services/ai/autonomy/closure_driver_service.rb:43` —
  `DutyCycleService.daily_limit_exceeded?(agent)` (a class method, budget check only)
- `server/app/services/ai/autonomy/goal_driven_scheduler_service.rb:99` — same class
  method, same use
- `server/app/services/ai/autonomy/closure_driver_service.rb:19` — a comment

The class is **not** dead code — `.daily_limit_exceeded?` /
`.duty_cycle_action_count` (`duty_cycle_service.rb:32-43`) are live and called from two
places. Only the instance method that would actually run a cycle,
`execute_cycle`, is unreachable. **Do not delete the class.**

Because `execute_cycle` never runs, the question "does any `Ai::RalphLoop` carry a
`duty_cycle_config`" is moot for this mechanism specifically — the code that would read
it never executes regardless of what any loop row contains. (Whether any such loop row
exists at all is a separate, still-open question — see the increment-3 investigation
report; it requires `list_ralph_loops`/`get_ralph_loop`, neither granted to this session,
and the live-DB break-glass path was declined as outward-facing production risk this
session could not authorize on a teammate's instruction alone.)

## Reason 2 — the plane that IS wired is gated by a setting no seed ever sets

A second, independent implementation of the same "OODA cycle" idea —
`Ai::Autonomy::RalphLoopClosureService#execute_cycle`
(`server/app/services/ai/autonomy/ralph_loop_closure_service.rb:12`) — **is** wired to a
real, currently-ticking cron:

- `worker/config/sidekiq.yml:520-524` — `ai_closure_driver`, every 15 minutes, class
  `AiClosureDriverJob`, comment: *"Inert until the operator enables the
  ai.autonomy.closure_driver_enabled SiteSetting (server-side gate)"*
- `worker/app/jobs/ai_closure_driver_job.rb` → `GET /api/v1/internal/ai/closure_driver/accounts`
  then `POST /api/v1/internal/ai/closure_driver/run` per eligible account
  (`server/config/routes.rb:587-588`, `server/app/controllers/api/v1/internal/ai/autonomy_controller.rb:33,43,47`)
- `server/app/services/ai/autonomy/closure_driver_service.rb:22,25-27` —
  `ClosureDriverService.enabled?` reads `SiteSetting.get("ai.autonomy.closure_driver_enabled")`,
  cast through `ActiveModel::Type::Boolean` `|| false`

`SiteSetting.get` (`server/app/models/site_setting.rb:49-51`) returns `nil` for a key with
no row, which casts to `false`. **No seed anywhere sets this key**, confirmed by
`command grep -rln "closure_driver_enabled" server/db/seeds extensions/system/server/db/seeds`
returning zero files. So by construction, on any install that has never had an operator
manually flip this setting through the admin UI, this driver has run zero times, on a
schedule that has ticked continuously since it was deployed. (Whether an operator has ever
flipped it on any specific live install is, again, a live-DB fact this session did not have
a tool grant or authorized access path to check.)

## Reason 3 — even enabled, the eligibility query requires a goal nothing creates

`ClosureDriverService#eligible_agents` (`closure_driver_service.rb:71-79`) is:

```ruby
@account.ai_agents
        .where(status: "active")
        .joins("INNER JOIN ai_agent_goals ON ai_agent_goals.ai_agent_id = ai_agents.id")
        .where(ai_agent_goals: { status: "active" })
        ...
```

An INNER JOIN against `ai_agent_goals` with `status: "active"` — an account with zero
active `Ai::AgentGoal` rows yields zero eligible agents, independent of Reason 2. Every
`Ai::AgentGoal.create!`/`.create` call site in the codebase is runtime-only; **no seed
anywhere creates a goal**:

- `server/app/services/ai/provisioning/adaptation_proposer_service.rb:1141`
- `server/app/services/ai/provisioning/plan_composer_service.rb:499`
- `server/app/services/ai/tools/agent_autonomy_tool.rb:501` (the `create_agent_goal` MCP verb)
- `server/app/services/ai/autonomy/goal_decomposition_service.rb:115` (sub-goals only —
  requires an existing goal to decompose from)
- `server/app/services/ai/missions/mission_composer.rb:328`

So a goal existing at all is an artifact of whether a mission ran, a plan was composed, or
an operator/agent explicitly called the MCP verb in this account's history — never a
guarantee. Confirmed via `mcp__powernode__platform_get_system_health` this session:
`missions: {active: 0, ...}` for the account in scope, consistent with (not proof of) no
current goal-generating activity. Whether any account clone anywhere holds an active goal
right now needs `list_agent_goals`, not granted this session.

## What this is not

This is not the health-check gap (filed and fixed separately this increment — see
`System::Platform::ScheduledHealthCheckService`,
`extensions/system/server/app/services/system/platform/scheduled_health_check_service.rb`).
That gap was a capability with no scheduler at all. This plane has *two* schedulers-worth
of intent (a `RalphLoop`-keyed one and an `Ai::AgentGoal`-keyed one) and neither has ever
produced a cycle — one because its only entry point is orphaned, the other because the
cron that calls it is switched off at the source and, if switched on, would still find
nothing eligible to run.

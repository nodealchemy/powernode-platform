# frozen_string_literal: true

# IMP-3e36e30d5c72 (incident, 2026-09-28 05:07-05:21). 20260928000000's
# backfill computed `(now - loop_row.started_at) * 1000).to_i` for a
# multi-week-old ai_ralph_loops row and wrote 2242823805 into duration_ms —
# `ActiveModel::RangeError: 2242823805 is out of range for
# ActiveModel::Type::Integer with limit 4 bytes`. Postgres `integer` is a
# 4-byte (int4) column, range -2,147,483,648..2,147,483,647; in MILLISECONDS
# that caps a safely-representable span at ~24.855 days
# (2,147,483,647 / 1000 / 86400). Any row whose started_at is older than that
# when it completes overflows, whether the write comes from this migration's
# raw SQL, from RalphLoop#calculate_duration's `update_columns`, or from any
# other model's equivalent before_save. rails-start runs pending migrations
# on every boot, so this crash-looped ops-hub Rails for ~14 minutes until the
# migration was stamped (not run) to restore service — see the sibling data
# migration this one clears the way for.
#
# SCOPE: every column found by grepping the app for the exact same unguarded
# `((completed_at_or_now - started_at) * 1000).to_i` pattern (or the
# ExecutionTrackable concern's equivalent), i.e. every column with the SAME
# EXPOSURE, not just the one that actually crashed:
#
#   Ai::RalphLoop#calculate_duration        -> ai_ralph_loops.duration_ms
#   Ai::RalphIteration#calculate_duration   -> ai_ralph_iterations.duration_ms
#   Ai::Mission#... (duration_ms=)          -> ai_missions.duration_ms
#   Ai::A2aTask#... (duration_ms=)          -> ai_a2a_tasks.duration_ms
#   McpToolExecution#calculate_execution_time -> mcp_tool_executions.execution_time_ms
#   Devops::SwarmDeployment (ExecutionTrackable)    -> devops_swarm_deployments.duration_ms
#   Devops::ContainerInstance (ExecutionTrackable)  -> devops_container_instances.duration_ms
#   Devops::DockerActivity (ExecutionTrackable)     -> devops_docker_activities.duration_ms
#   Devops::IntegrationExecution (ExecutionTrackable) -> devops_integration_executions.duration_ms
#
# NOT exhaustive: review found three more int4 columns with the same write
# (ai_dag_executions, ai_execution_traces, ai_agent_executions duration_ms).
# They fail at runtime, not at boot, and are widened in a follow-up.
#
# NOT WIDENED, checked and confirmed a DIFFERENT (safe) exposure class:
#   - Devops::PipelineRun, Devops::StepExecution (ExecutionTrackable's
#     duration_SECONDS branch), Devops::GitPipeline, Devops::GitPipelineJob —
#     all write `(completed_at - started_at).to_i` in SECONDS, not
#     milliseconds, into an int4 column. Same column WIDTH, but the overflow
#     threshold is ~68 YEARS (2,147,483,647 seconds), not ~25 days —
#     practically unreachable, left alone.
#   - Ai::DiscoveryResult#duration_ms is a plain Ruby METHOD, never persisted
#     (no duration_ms column on ai_discovery_results at all) — Ruby Integers
#     don't overflow, and nothing writes this value to a 4-byte DB column.
#   - Checked ai_ralph_tasks (named as an example to check): no
#     duration/elapsed column of any kind exists on that table. Not affected.
#
# VALUE RANGES BEING WRITTEN, per the operator's request (the check that was
# missing last time): every widened column above is fed EXCLUSIVELY by
# `(<a timestamp diff> * 1000).to_i` — milliseconds, always >= 0 in practice
# (a few call sites additionally clamp via `[x, 0].max`) — so the write is
# bounded by wall-clock elapsed time only, unbounded upward, was int4-capped
# at ~24.855 days, and bigint (int8, -9,223,372,036,854,775,808 ..
# 9,223,372,036,854,775,807) caps it at ~292 MILLION years — no realistic
# lifetime of this platform reaches that ceiling.
class WidenDurationMsColumnsToBigint < ActiveRecord::Migration[8.1]
  COLUMNS = [
    [ :ai_ralph_loops, :duration_ms ],
    [ :ai_ralph_iterations, :duration_ms ],
    [ :ai_missions, :duration_ms ],
    [ :ai_a2a_tasks, :duration_ms ],
    [ :mcp_tool_executions, :execution_time_ms ],
    [ :devops_swarm_deployments, :duration_ms ],
    [ :devops_container_instances, :duration_ms ],
    [ :devops_docker_activities, :duration_ms ],
    [ :devops_integration_executions, :duration_ms ]
  ].freeze

  def up
    COLUMNS.each { |table, column| change_column table, column, :bigint }
  end

  # Narrowing back to int4 fails on any row already past the int4 ceiling; that
  # is the correct outcome (the rollback would otherwise silently lose data).
  def down
    COLUMNS.each { |table, column| change_column table, column, :integer }
  end
end

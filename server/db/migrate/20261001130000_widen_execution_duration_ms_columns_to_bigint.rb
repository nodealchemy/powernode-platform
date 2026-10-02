# frozen_string_literal: true

# IMP-36483b880322, the follow-up 20260928010000 named but did not do. Four more
# int4 duration_ms columns are written with the same wall-clock
# `((now - started_at) * 1000)` span, so any execution older than ~24.855 days
# (2_147_483_647 ms) raises ActiveModel::RangeError when it completes:
#
#   Ai::A2a::DagExecutor           -> ai_dag_executions.duration_ms
#   Ai::ExecutionTrace#complete!   -> ai_execution_traces.duration_ms
#   Ai::ExecutionTraceSpan#complete! -> ai_execution_trace_spans.duration_ms
#   Ai::Agent::Execution concern   -> ai_agent_executions.duration_ms
#
# The spans table is included because its writer stores the same elapsed wall
# time, not a bounded sub-step figure.
#
# SCHEMA ONLY. No data rewrite. Widening int4 -> int8 rewrites the table, and
# rails-start runs pending migrations on EVERY boot, so this must never be the
# reason Rails does not come up (see 20260928000000's incident): each column is
#   - skipped when it is already bigint (schema.rb already carries the result on
#     a fresh database, which loads it instead of replaying migrations) or the
#     table/column is absent;
#   - widened in its own transaction under a short lock_timeout and a bounded
#     statement_timeout, so a busy table cannot stall boot;
#   - on any failure logged loudly and left int4 (the pre-existing, runtime-only
#     failure mode) instead of raising out of the migration.
# A skipped column is stamped applied and NOT retried on the next boot, so after
# deploy verify each one (`\d ai_agent_executions` etc., or
# SELECT table_name, data_type FROM information_schema.columns
#  WHERE column_name = 'duration_ms' AND table_name IN (<the four tables>)) and
# widen any that still say integer with
#   ALTER TABLE <table> ALTER COLUMN duration_ms TYPE bigint;
# The model spec asserts every one is bigint on a freshly loaded schema only.
class WidenExecutionDurationMsColumnsToBigint < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  COLUMNS = [
    [ :ai_dag_executions, :duration_ms ],
    [ :ai_execution_traces, :duration_ms ],
    [ :ai_execution_trace_spans, :duration_ms ],
    [ :ai_agent_executions, :duration_ms ]
  ].freeze

  LOCK_TIMEOUT = "5s"
  STATEMENT_TIMEOUT = "120s"

  def up
    COLUMNS.each { |table, column| widen(table, column) }
  end

  # Narrowing back fails on any row already past the int4 ceiling; that is the
  # correct outcome (the rollback would otherwise silently lose data).
  def down
    COLUMNS.each do |table, column|
      next unless column_exists?(table, column)

      change_column table, column, :integer
    end
  end

  private

  def widen(table, column)
    return say("#{table}.#{column}: table or column absent, skipped") unless column_exists?(table, column)
    return say("#{table}.#{column}: already bigint, skipped") if bigint?(table, column)

    transaction do
      execute "SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'"
      execute "SET LOCAL statement_timeout = '#{STATEMENT_TIMEOUT}'"
      change_column table, column, :bigint
    end
    say("#{table}.#{column}: widened to bigint")
  rescue StandardError => e
    message = "#{table}.#{column} NOT widened (#{e.class}: #{e.message.lines.first.to_s.strip}); " \
              "left int4, spans over ~24.8 days will raise at completion until widened by hand: " \
              "ALTER TABLE #{table} ALTER COLUMN #{column} TYPE bigint"
    say("WARNING: #{message}")
    Rails.logger.warn("[WidenExecutionDurationMsColumnsToBigint] #{message}")
  end

  def bigint?(table, column)
    connection.columns(table).find { |c| c.name == column.to_s }&.sql_type == "bigint"
  end
end

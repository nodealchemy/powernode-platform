# frozen_string_literal: true

# D4 — one evaluation per (execution, task).
#
# The judge is now driven from a worker job, and a worker job retries. Without
# a key, a retried completion writes a second Ai::EvaluationResult for the same
# work, which double-counts in agent_score_trends, in the trust quality signal
# and in SkillVersion effectiveness — three places where a duplicate is
# invisible rather than loud.
#
# task_id is nullable because an evaluation can be driven by something other
# than a dev-loop task, so the index is NULLS NOT DISTINCT: without it two rows
# with the same execution_id and no task would both be accepted by Postgres,
# which is exactly the retry case for a non-task-driven evaluation.
#
# No dedupe pass precedes the index. The table is unwritten in production — the
# only writer was EvaluationService#evaluate_execution, which had zero callers
# (vision audit 2026-09-10 §6.3: "ai_evaluation_results is never written") — so
# there is nothing to collapse. If that turns out to be false somewhere, this
# migration fails loudly at migrate time rather than silently dropping a row.
class AddEvaluationIdempotencyKey < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_evaluation_results, :task_id, :uuid

    add_index :ai_evaluation_results, %i[execution_id task_id],
              unique: true, nulls_not_distinct: true,
              name: "index_ai_evaluation_results_on_execution_and_task"
  end
end

# frozen_string_literal: true

# F-D5-1 dedupe — ONE judge attempt per (execution_id, task_id). A degraded
# verdict writes no ai_evaluation_results row, so result idempotency could not
# see its retry: the worker's Sidekiq retry after a 408 made a second paid
# judge call. With this index a retry answers from the first attempt.
#
# The same key and NULLS NOT DISTINCT as the ai_evaluation_results unique
# index, so a completion that names no task is one attempt, not an unlimited
# number. The table is new (20260911181631). If a database somehow holds
# duplicates, this fails loudly instead of deleting ledger rows the cap counts.
class AddUniqueExecutionTaskIndexToAiEvaluationAttempts < ActiveRecord::Migration[8.1]
  def change
    add_index :ai_evaluation_attempts, %i[execution_id task_id],
              unique: true, nulls_not_distinct: true,
              name: "index_ai_evaluation_attempts_on_execution_and_task"
  end
end

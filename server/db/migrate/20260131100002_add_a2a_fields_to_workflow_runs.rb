# frozen_string_literal: true

class AddA2aFieldsToWorkflowRuns < ActiveRecord::Migration[8.0]
  def change
    # Add A2A context tracking to workflow runs
    add_column :ai_workflow_runs, :a2a_context_id, :uuid
    add_column :ai_workflow_runs, :a2a_task_id, :uuid
    add_column :ai_workflow_runs, :a2a_artifacts, :jsonb, default: []

    # Index for A2A context lookups
    add_index :ai_workflow_runs, :a2a_context_id, where: "a2a_context_id IS NOT NULL"
    add_index :ai_workflow_runs, :a2a_task_id, where: "a2a_task_id IS NOT NULL"

    # Add foreign key to A2A task (optional relationship)
    add_foreign_key :ai_workflow_runs, :ai_a2a_tasks, column: :a2a_task_id, on_delete: :nullify
  end
end

# frozen_string_literal: true

class CreateBatchWorkflowRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :batch_workflow_runs, id: :uuid do |t|
      t.string :batch_id, null: false, index: { unique: true }
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :user, null: true, foreign_key: true, type: :uuid

      # Batch configuration
      t.integer :total_workflows, null: false, default: 0
      t.integer :completed_workflows, default: 0
      t.integer :successful_workflows, default: 0
      t.integer :failed_workflows, default: 0

      # Status tracking
      t.string :status, null: false, default: 'pending'
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms

      # Data storage
      t.jsonb :configuration, default: {}
      t.jsonb :results, default: []
      t.jsonb :statistics, default: {}
      t.jsonb :error_details, default: {}

      t.timestamps
    end

    add_index :batch_workflow_runs, :status
    add_index :batch_workflow_runs, :created_at
    add_index :batch_workflow_runs, [:account_id, :status]
    add_index :batch_workflow_runs, [:account_id, :created_at]

    # Add check constraint for status
    add_check_constraint :batch_workflow_runs,
      "status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')",
      name: 'batch_workflow_runs_status_check'

    # Add check constraint for workflow counts
    add_check_constraint :batch_workflow_runs,
      "completed_workflows <= total_workflows",
      name: 'batch_workflow_runs_completed_check'

    add_check_constraint :batch_workflow_runs,
      "successful_workflows + failed_workflows <= completed_workflows",
      name: 'batch_workflow_runs_success_failed_check'
  end
end
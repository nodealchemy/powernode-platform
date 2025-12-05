# frozen_string_literal: true

class CreateAiWorkflowRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_workflow_runs, id: :uuid do |t|
      t.references :ai_workflow, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :triggered_by_user, null: true, foreign_key: { to_table: :users }, type: :uuid
      t.references :ai_workflow_trigger, null: true, foreign_key: true, type: :uuid
      t.string :run_id, null: false, limit: 100
      t.string :status, null: false, default: 'initializing'
      t.string :trigger_type, null: false
      t.jsonb :input_variables, null: false, default: {}
      t.jsonb :output_variables, null: false, default: {}
      t.jsonb :runtime_context, null: false, default: {}
      t.jsonb :error_details, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.integer :total_nodes, null: false, default: 0
      t.integer :completed_nodes, null: false, default: 0
      t.integer :failed_nodes, null: false, default: 0
      t.integer :duration_ms
      t.decimal :total_cost, precision: 10, scale: 6, default: 0.0
      t.timestamps

      t.index [:ai_workflow_id, :status]
      t.index [:account_id, :status]
      t.index [:run_id], unique: true
      t.index :trigger_type
      t.index :started_at
      t.index :completed_at
      t.index :total_cost
    end

    add_check_constraint :ai_workflow_runs,
      "status IN ('initializing', 'running', 'completed', 'failed', 'cancelled', 'waiting_approval')",
      name: 'ai_workflow_runs_status_check'

    add_check_constraint :ai_workflow_runs,
      "trigger_type IN ('manual', 'webhook', 'schedule', 'event', 'api_call')",
      name: 'ai_workflow_runs_trigger_type_check'

    add_check_constraint :ai_workflow_runs,
      "completed_nodes <= total_nodes",
      name: 'ai_workflow_runs_progress_check'

    add_check_constraint :ai_workflow_runs,
      "total_cost >= 0",
      name: 'ai_workflow_runs_cost_check'
  end
end
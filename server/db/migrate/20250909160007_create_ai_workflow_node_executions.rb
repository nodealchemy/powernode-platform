# frozen_string_literal: true

class CreateAiWorkflowNodeExecutions < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_workflow_node_executions, id: :uuid do |t|
      t.references :ai_workflow_run, null: false, foreign_key: true, type: :uuid
      t.references :ai_workflow_node, null: false, foreign_key: true, type: :uuid
      t.references :ai_agent_execution, null: true, foreign_key: true, type: :uuid
      t.string :execution_id, null: false, limit: 100
      t.string :status, null: false, default: 'pending'
      t.string :node_id, null: false, limit: 100
      t.string :node_type, null: false, limit: 50
      t.jsonb :input_data, null: false, default: {}
      t.jsonb :output_data, null: false, default: {}
      t.jsonb :configuration_snapshot, null: false, default: {}
      t.jsonb :error_details, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.integer :duration_ms
      t.decimal :cost, precision: 10, scale: 6, default: 0.0
      t.integer :retry_count, null: false, default: 0
      t.integer :max_retries, null: false, default: 0
      t.timestamps

      t.index [:ai_workflow_run_id, :node_id], unique: true, name: 'index_node_executions_on_run_node'
      t.index [:ai_workflow_run_id, :status]
      t.index [:execution_id], unique: true
      t.index :node_type
      t.index :started_at
      t.index :completed_at
      t.index :cost
    end

    add_check_constraint :ai_workflow_node_executions,
      "status IN ('pending', 'running', 'completed', 'failed', 'cancelled', 'skipped', 'waiting_approval')",
      name: 'ai_workflow_node_executions_status_check'

    add_check_constraint :ai_workflow_node_executions,
      "retry_count >= 0",
      name: 'ai_workflow_node_executions_retry_count_check'

    add_check_constraint :ai_workflow_node_executions,
      "max_retries >= 0",
      name: 'ai_workflow_node_executions_max_retries_check'

    add_check_constraint :ai_workflow_node_executions,
      "retry_count <= max_retries",
      name: 'ai_workflow_node_executions_retry_limit_check'

    add_check_constraint :ai_workflow_node_executions,
      "cost >= 0",
      name: 'ai_workflow_node_executions_cost_check'
  end
end
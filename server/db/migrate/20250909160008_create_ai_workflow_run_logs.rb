# frozen_string_literal: true

class CreateAiWorkflowRunLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_workflow_run_logs, id: :uuid do |t|
      t.references :ai_workflow_run, null: false, foreign_key: true, type: :uuid
      t.references :ai_workflow_node_execution, null: true, foreign_key: true, type: :uuid
      t.string :log_level, null: false, default: 'info'
      t.string :event_type, null: false
      t.text :message, null: false
      t.jsonb :context_data, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.string :node_id, limit: 100
      t.string :source, limit: 100
      t.datetime :logged_at, null: false
      t.timestamps

      t.index [ :ai_workflow_run_id, :logged_at ]
      t.index [ :ai_workflow_run_id, :log_level ]
      t.index [ :ai_workflow_run_id, :event_type ]
      t.index [ :node_id, :logged_at ]
      t.index :logged_at
      t.index :event_type
    end

    add_check_constraint :ai_workflow_run_logs,
      "log_level IN ('debug', 'info', 'warn', 'error', 'fatal')",
      name: 'ai_workflow_run_logs_level_check'

    add_check_constraint :ai_workflow_run_logs,
      "event_type IN ('workflow_started', 'workflow_completed', 'workflow_failed', 'workflow_cancelled', 'node_started', 'node_completed', 'node_failed', 'node_cancelled', 'node_skipped', 'variable_updated', 'condition_evaluated', 'error_handled', 'retry_attempted', 'approval_requested', 'approval_granted', 'approval_denied', 'webhook_sent', 'api_called', 'data_transformed')",
      name: 'ai_workflow_run_logs_event_type_check'
  end
end

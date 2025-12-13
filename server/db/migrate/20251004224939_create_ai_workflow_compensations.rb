# frozen_string_literal: true

class CreateAiWorkflowCompensations < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_workflow_compensations, id: :uuid do |t|
      t.uuid :ai_workflow_run_id, null: false
      t.string :compensation_id, null: false
      t.uuid :ai_workflow_node_execution_id, null: false
      t.string :compensation_type, null: false, default: 'rollback'
      t.string :trigger_reason, null: false
      t.string :status, null: false, default: 'pending'
      t.jsonb :original_action, null: false, default: {}
      t.jsonb :compensation_action, null: false, default: {}
      t.jsonb :compensation_result, default: {}
      t.jsonb :metadata, default: {}
      t.integer :retry_count, default: 0
      t.integer :max_retries, default: 3
      t.timestamp :executed_at
      t.timestamp :completed_at
      t.timestamp :failed_at

      t.timestamps
    end

    # Composite and unique indexes only
    add_index :ai_workflow_compensations, :compensation_id, unique: true
    add_index :ai_workflow_compensations, [ :ai_workflow_run_id, :status ], name: 'index_compensations_on_run_and_status'

    add_foreign_key :ai_workflow_compensations, :ai_workflow_runs, on_delete: :cascade
    add_foreign_key :ai_workflow_compensations, :ai_workflow_node_executions, on_delete: :cascade
  end
end

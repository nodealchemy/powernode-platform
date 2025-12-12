# frozen_string_literal: true

class CreateAiWorkflowExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_workflow_executions, id: :uuid do |t|
      # Foreign key relationships
      t.uuid :account_id, null: false
      t.uuid :user_id, null: false

      # Workflow identification
      t.string :name, null: false, limit: 255
      t.string :execution_id, null: false, limit: 255

      # Workflow execution tracking
      t.string :status, null: false, default: 'initializing', limit: 50
      t.json :configuration, null: false, default: '{}'
      t.json :results, default: '[]'
      t.json :metadata, default: '{}'

      # Timing information
      t.timestamp :started_at
      t.timestamp :completed_at

      # Error handling
      t.text :error_message

      # Standard timestamps
      t.timestamps

      # Indexes for performance
      t.index :account_id, name: 'index_ai_workflow_executions_on_account_id'
      t.index :user_id, name: 'index_ai_workflow_executions_on_user_id'
      t.index :execution_id, unique: true, name: 'index_ai_workflow_executions_on_execution_id'
      t.index :status, name: 'index_ai_workflow_executions_on_status'
      t.index :created_at, name: 'index_ai_workflow_executions_on_created_at'
      t.index [ :account_id, :status ], name: 'index_ai_workflow_executions_on_account_id_and_status'
      t.index [ :account_id, :created_at ], name: 'index_ai_workflow_executions_on_account_id_and_created_at'

      # Foreign key constraints
      t.foreign_key :accounts, on_delete: :cascade
      t.foreign_key :users, on_delete: :cascade
    end
  end
end

# frozen_string_literal: true

class CreateIntegrationExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :integration_executions, id: :uuid do |t|
      # Relationships
      t.references :integration_instance, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :triggered_by_user, foreign_key: { to_table: :users }, type: :uuid

      # Execution Identity
      t.string :execution_id, null: false  # Unique execution identifier
      t.string :status, null: false, default: "pending"  # pending, running, completed, failed, cancelled

      # Execution Details
      t.jsonb :input_data, default: {}
      t.jsonb :output_data, default: {}
      t.jsonb :error_details, default: {}

      # Timing
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms

      # Trigger Information
      t.string :trigger_type  # manual, webhook, scheduled, workflow, api
      t.string :trigger_source  # Source identifier (webhook ID, schedule ID, etc.)
      t.jsonb :trigger_metadata, default: {}

      # Retry Information
      t.integer :attempt_number, default: 1
      t.integer :max_attempts, default: 3
      t.datetime :next_retry_at
      t.uuid :parent_execution_id  # If this is a retry

      # Resource Usage
      t.decimal :cost_estimate, precision: 10, scale: 6
      t.jsonb :resource_usage, default: {}

      t.timestamps
    end

    add_index :integration_executions, :execution_id, unique: true
    add_index :integration_executions, :status
    add_index :integration_executions, :trigger_type
    add_index :integration_executions, [ :integration_instance_id, :status ], name: "idx_executions_instance_status"
    add_index :integration_executions, [ :account_id, :created_at ], name: "idx_executions_account_created"
    add_index :integration_executions, :parent_execution_id
  end
end

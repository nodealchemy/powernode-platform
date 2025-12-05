# frozen_string_literal: true

class CreateAiAgentExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_executions, id: :uuid do |t|
      t.uuid :ai_agent_id, null: false
      t.uuid :account_id, null: false
      t.uuid :user_id, null: false
      t.uuid :ai_provider_id, null: false
      t.string :execution_id, null: false, limit: 100
      t.string :status, null: false, default: 'pending'
      t.jsonb :input_parameters, null: false, default: {}
      t.jsonb :output_data, default: {}
      t.jsonb :execution_context, default: {}
      t.text :error_message
      t.jsonb :error_details, default: {}
      t.timestamp :started_at
      t.timestamp :completed_at
      t.integer :duration_ms
      t.integer :tokens_used, default: 0
      t.decimal :cost_usd, precision: 10, scale: 4, default: 0
      t.jsonb :performance_metrics, default: {}
      t.uuid :parent_execution_id
      t.string :webhook_url
      t.jsonb :webhook_data, default: {}
      t.integer :webhook_attempts, default: 0
      t.timestamp :webhook_last_attempt_at
      t.string :webhook_status
      t.timestamps

      t.index :ai_agent_id
      t.index :account_id
      t.index :user_id
      t.index :ai_provider_id
      t.index :execution_id, unique: true
      t.index :status
      t.index :parent_execution_id
      t.index :started_at
      t.index :completed_at
      t.index [:account_id, :status]
      t.index [:ai_agent_id, :status]
      t.index :webhook_status

      t.foreign_key :ai_agents, on_delete: :cascade
      t.foreign_key :accounts, on_delete: :cascade
      t.foreign_key :users, on_delete: :restrict
      t.foreign_key :ai_providers, on_delete: :restrict
      t.foreign_key :ai_agent_executions, column: :parent_execution_id, on_delete: :nullify
    end
  end
end
# frozen_string_literal: true

class CreateAiMemoryPools < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_memory_pools, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid, index: true
      t.string :pool_id
      t.string :name
      t.string :pool_type
      t.string :scope
      t.uuid :owner_agent_id
      t.uuid :team_id
      t.uuid :task_execution_id
      t.jsonb :data, default: {}
      t.jsonb :access_control, default: {}
      t.jsonb :metadata, default: {}
      t.jsonb :retention_policy, default: {}
      t.integer :version, default: 1
      t.integer :data_size_bytes, default: 0
      t.boolean :persist_across_executions, default: false
      t.datetime :expires_at
      t.datetime :last_accessed_at
      t.timestamps
    end
    add_index :ai_memory_pools, :pool_id, unique: true
    add_index :ai_memory_pools, [:account_id, :scope]
    add_index :ai_memory_pools, :owner_agent_id
    add_index :ai_memory_pools, :team_id
    add_index :ai_memory_pools, :task_execution_id
  end
end

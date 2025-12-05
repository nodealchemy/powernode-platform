# frozen_string_literal: true

class CreateAiSharedContextPools < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_shared_context_pools, id: :uuid do |t|
      t.uuid :ai_workflow_run_id, null: false
      t.string :pool_id, null: false
      t.string :pool_type, null: false, default: 'shared_memory'
      t.string :scope, null: false, default: 'workflow'
      t.jsonb :context_data, null: false, default: {}
      t.jsonb :access_control, default: {}
      t.jsonb :metadata, default: {}
      t.string :created_by_agent_id
      t.string :owner_agent_id
      t.integer :version, null: false, default: 1
      t.timestamp :last_accessed_at
      t.timestamp :expires_at

      t.timestamps
    end

    add_index :ai_shared_context_pools, :ai_workflow_run_id
    add_index :ai_shared_context_pools, :pool_id, unique: true
    add_index :ai_shared_context_pools, :pool_type
    add_index :ai_shared_context_pools, :scope
    add_index :ai_shared_context_pools, :owner_agent_id
    add_index :ai_shared_context_pools, [:ai_workflow_run_id, :pool_type], name: 'index_context_pools_on_run_and_type'
    add_index :ai_shared_context_pools, [:ai_workflow_run_id, :scope], name: 'index_context_pools_on_run_and_scope'

    add_foreign_key :ai_shared_context_pools, :ai_workflow_runs, on_delete: :cascade
  end
end

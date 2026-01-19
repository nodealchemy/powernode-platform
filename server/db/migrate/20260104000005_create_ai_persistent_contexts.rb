# frozen_string_literal: true

class CreateAiPersistentContexts < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_persistent_contexts, id: :uuid do |t|
      # Relationships
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :ai_agent, foreign_key: true, type: :uuid  # null = account-wide context
      t.references :created_by_user, foreign_key: { to_table: :users }, type: :uuid

      # Context Identity
      t.string :context_id, null: false  # Unique context identifier
      t.string :name, null: false
      t.text :description

      # Context Classification
      t.string :context_type, null: false  # agent_memory, knowledge_base, shared_context
      t.string :scope, null: false  # account, agent, team, workflow

      # Context Data
      t.jsonb :context_data, default: {}  # The actual context content
      t.jsonb :metadata, default: {}  # Additional metadata

      # Access Control
      t.jsonb :access_control, default: {}  # Who can access this context

      # Retention Policy
      t.jsonb :retention_policy, default: {}  # How long to keep, cleanup rules
      t.datetime :expires_at
      t.datetime :archived_at

      # Versioning
      t.integer :version, default: 1

      # Size Tracking
      t.integer :data_size_bytes, default: 0
      t.integer :entry_count, default: 0

      # Usage Statistics
      t.datetime :last_accessed_at
      t.integer :access_count, default: 0
      t.datetime :last_modified_at

      t.timestamps
    end

    add_index :ai_persistent_contexts, :context_id, unique: true
    add_index :ai_persistent_contexts, :context_type
    add_index :ai_persistent_contexts, :scope
    add_index :ai_persistent_contexts, [:account_id, :context_type], name: "idx_contexts_account_type"
    add_index :ai_persistent_contexts, [:account_id, :ai_agent_id], name: "idx_contexts_account_agent"
    add_index :ai_persistent_contexts, :expires_at
    add_index :ai_persistent_contexts, :archived_at
  end
end

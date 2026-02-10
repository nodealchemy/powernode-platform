# frozen_string_literal: true

class CreateMemoryTierSystem < ActiveRecord::Migration[8.0]
  def up
    # Short-term memory - Redis-backed with DB persistence
    create_table :ai_agent_short_term_memories, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }
      t.string :session_id, null: false
      t.string :memory_key, null: false
      t.jsonb :memory_value, null: false
      t.string :memory_type, default: "general"
      t.integer :ttl_seconds, default: 3600
      t.datetime :expires_at
      t.integer :access_count, default: 0
      t.datetime :last_accessed_at
      t.timestamps
    end

    add_index :ai_agent_short_term_memories, [:agent_id, :session_id, :memory_key],
              unique: true, name: "idx_short_term_memories_agent_session_key"
    add_index :ai_agent_short_term_memories, :expires_at

    # Shared knowledge base with pgvector embeddings
    create_table :ai_shared_knowledges, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.string :title, null: false
      t.text :content, null: false
      t.string :content_type, default: "text"
      t.string :source_type
      t.uuid :source_id
      t.string :tags, array: true, default: []
      t.string :access_level, default: "team"
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users }, null: true
      t.jsonb :provenance, default: {}
      t.string :integrity_hash
      t.decimal :quality_score, precision: 5, scale: 4
      t.integer :usage_count, default: 0
      t.datetime :last_used_at
      t.timestamps
    end

    # Add pgvector embedding column
    execute "ALTER TABLE ai_shared_knowledges ADD COLUMN embedding vector(1536)"

    # HNSW index for cosine similarity search
    execute "CREATE INDEX index_ai_shared_knowledges_on_embedding ON ai_shared_knowledges USING hnsw (embedding vector_cosine_ops)"

    add_index :ai_shared_knowledges, :tags, using: :gin
    add_index :ai_shared_knowledges, :access_level
    add_index :ai_shared_knowledges, [:source_type, :source_id]
  end

  def down
    drop_table :ai_shared_knowledges
    drop_table :ai_agent_short_term_memories
  end
end

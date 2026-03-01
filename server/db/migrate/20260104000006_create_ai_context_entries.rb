# frozen_string_literal: true

class CreateAiContextEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_context_entries, id: :uuid do |t|
      # Relationships
      t.references :ai_persistent_context, null: false, foreign_key: true, type: :uuid
      t.references :created_by_user, foreign_key: { to_table: :users }, type: :uuid
      t.references :ai_agent, foreign_key: true, type: :uuid  # Agent that created this entry

      # Entry Identity
      t.string :entry_key, null: false  # Key within the context
      t.string :entry_type  # fact, memory, preference, knowledge, tool_result

      # Entry Content
      t.jsonb :content, null: false, default: {}
      t.text :content_text  # Searchable text content
      t.jsonb :metadata, default: {}

      # Importance & Relevance
      t.decimal :importance_score, precision: 5, scale: 4, default: 0.5
      t.decimal :relevance_decay_rate, precision: 5, scale: 4, default: 0.0
      t.datetime :last_relevance_update

      # Source Tracking
      t.string :source_type  # user_input, agent_output, workflow, import, api
      t.string :source_id  # Reference to the source

      # Versioning
      t.integer :version, default: 1
      t.uuid :previous_version_id

      # Lifecycle
      t.datetime :expires_at
      t.datetime :archived_at

      # Usage
      t.integer :access_count, default: 0
      t.datetime :last_accessed_at

      t.timestamps
    end

    add_index :ai_context_entries, [ :ai_persistent_context_id, :entry_key ], unique: true, name: "idx_entries_context_key"
    add_index :ai_context_entries, :entry_type
    add_index :ai_context_entries, :source_type
    add_index :ai_context_entries, :importance_score
    add_index :ai_context_entries, :expires_at
    add_index :ai_context_entries, :archived_at
    add_index :ai_context_entries, :previous_version_id

    # Add vector column for embeddings if pgvector is available
    # This is done separately to avoid migration failures in environments without pgvector
    add_embedding_column_if_available
  end

  private

  def add_embedding_column_if_available
    # Check if pgvector extension is available
    result = execute("SELECT 1 FROM pg_extension WHERE extname = 'vector'").to_a
    if result.any?
      add_column :ai_context_entries, :embedding, :vector, limit: 1536
      # Note: Vector index should be added separately using:
      # CREATE INDEX idx_entries_embedding ON ai_context_entries USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
    else
      Rails.logger.info "pgvector extension not available - skipping embedding column"
    end
  rescue StandardError => e
    Rails.logger.warn "Could not add embedding column: #{e.message}"
  end
end

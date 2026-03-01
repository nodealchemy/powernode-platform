# frozen_string_literal: true

class AddMemoryTaxonomyToContextEntries < ActiveRecord::Migration[8.0]
  def change
    # Add memory type classification
    add_column :ai_context_entries, :memory_type, :string, default: "factual"

    # Add confidence scoring for factual vs learned memories
    add_column :ai_context_entries, :confidence_score, :decimal, precision: 5, scale: 4, default: 1.0

    # Add decay rate for experiential memories
    unless column_exists?(:ai_context_entries, :decay_rate)
      add_column :ai_context_entries, :decay_rate, :decimal, precision: 5, scale: 4, default: 0.0
    end

    # Add context for memory retrieval
    add_column :ai_context_entries, :context_tags, :jsonb, default: [], null: false

    # Add source tracking for experiential memories
    add_column :ai_context_entries, :task_context, :jsonb, default: {}
    add_column :ai_context_entries, :outcome_success, :boolean

    # Add embedding column if pgvector is available and not already present
    add_embedding_column_if_needed

    # Add indexes
    add_index :ai_context_entries, :memory_type
    add_index :ai_context_entries, :confidence_score
    add_index :ai_context_entries, :context_tags, using: :gin
    add_index :ai_context_entries, :outcome_success

    # Add check constraint for memory types
    add_check_constraint :ai_context_entries,
      "memory_type IN ('factual', 'experiential', 'working')",
      name: "ai_context_entries_memory_type_check"
  end

  private

  def add_embedding_column_if_needed
    return if column_exists?(:ai_context_entries, :embedding)

    # Check if pgvector extension is available
    result = execute("SELECT 1 FROM pg_extension WHERE extname = 'vector'").to_a
    if result.any?
      add_column :ai_context_entries, :embedding, :vector, limit: 1536

      # Add vector similarity search index
      # Using ivfflat for approximate nearest neighbor search
      execute <<-SQL
        CREATE INDEX IF NOT EXISTS idx_context_entries_embedding
        ON ai_context_entries
        USING ivfflat (embedding vector_cosine_ops)
        WITH (lists = 100);
      SQL
    else
      Rails.logger.info "pgvector extension not available - skipping embedding column"
    end
  rescue StandardError => e
    Rails.logger.warn "Could not add embedding column: #{e.message}"
  end
end

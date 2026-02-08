# frozen_string_literal: true

class MigrateEmbeddingsToPgvector < ActiveRecord::Migration[8.0]
  def up
    # 1. ai_context_entries — add vector column (was skipped without pgvector)
    unless column_exists?(:ai_context_entries, :embedding)
      execute "ALTER TABLE ai_context_entries ADD COLUMN embedding vector(1536)"
    end
    execute <<~SQL
      CREATE INDEX IF NOT EXISTS idx_context_entries_embedding
      ON ai_context_entries USING hnsw (embedding vector_cosine_ops);
    SQL

    # 2. ai_document_chunks — convert jsonb to vector
    execute "ALTER TABLE ai_document_chunks ADD COLUMN embedding_vector vector(1536)"
    execute <<~SQL
      UPDATE ai_document_chunks
      SET embedding_vector = embedding::text::vector
      WHERE embedding IS NOT NULL AND embedding != '[]'::jsonb;
    SQL
    remove_column :ai_document_chunks, :embedding
    rename_column :ai_document_chunks, :embedding_vector, :embedding
    execute <<~SQL
      CREATE INDEX IF NOT EXISTS idx_document_chunks_embedding
      ON ai_document_chunks USING hnsw (embedding vector_cosine_ops);
    SQL

    # 3. ai_rag_queries — convert jsonb to vector
    execute "ALTER TABLE ai_rag_queries ADD COLUMN query_embedding_vector vector(1536)"
    execute <<~SQL
      UPDATE ai_rag_queries
      SET query_embedding_vector = query_embedding::text::vector
      WHERE query_embedding IS NOT NULL AND query_embedding != '[]'::jsonb;
    SQL
    remove_column :ai_rag_queries, :query_embedding
    rename_column :ai_rag_queries, :query_embedding_vector, :query_embedding
    execute <<~SQL
      CREATE INDEX IF NOT EXISTS idx_rag_queries_embedding
      ON ai_rag_queries USING hnsw (query_embedding vector_cosine_ops);
    SQL
  end

  def down
    remove_index :ai_context_entries, name: :idx_context_entries_embedding, if_exists: true
    remove_column :ai_context_entries, :embedding if column_exists?(:ai_context_entries, :embedding)

    remove_index :ai_document_chunks, name: :idx_document_chunks_embedding, if_exists: true
    execute "ALTER TABLE ai_document_chunks ADD COLUMN embedding_jsonb jsonb DEFAULT '[]'"
    remove_column :ai_document_chunks, :embedding
    rename_column :ai_document_chunks, :embedding_jsonb, :embedding

    remove_index :ai_rag_queries, name: :idx_rag_queries_embedding, if_exists: true
    execute "ALTER TABLE ai_rag_queries ADD COLUMN query_embedding_jsonb jsonb DEFAULT '[]'"
    remove_column :ai_rag_queries, :query_embedding
    rename_column :ai_rag_queries, :query_embedding_jsonb, :query_embedding
  end
end

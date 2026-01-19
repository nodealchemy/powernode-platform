# frozen_string_literal: true

# RAG System Tables - Knowledge-Augmented Agents
#
# Revenue Model: Storage fees + query pricing + embedding fees
# - Storage: $0.10-0.25/GB/month
# - Embeddings: $0.0001-0.0004/1K tokens
# - Queries: $0.001-0.01/query based on complexity
# - Enterprise: dedicated vector clusters ($999+/mo)
#
class CreateRagSystemTables < ActiveRecord::Migration[8.0]
  def change
    # ==========================================================================
    # KNOWLEDGE BASES - Collections of documents for RAG
    # ==========================================================================
    create_table :ai_knowledge_bases, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false
      t.string :description
      t.string :status, null: false, default: "active"
      t.string :embedding_model, null: false, default: "text-embedding-3-small"
      t.string :embedding_provider, null: false, default: "openai"
      t.integer :embedding_dimensions, default: 1536
      t.string :chunking_strategy, null: false, default: "recursive"
      t.integer :chunk_size, default: 1000
      t.integer :chunk_overlap, default: 200
      t.jsonb :metadata_schema, default: {}
      t.jsonb :settings, default: {}
      t.boolean :is_public, null: false, default: false
      t.integer :document_count, default: 0
      t.integer :chunk_count, default: 0
      t.bigint :total_tokens, default: 0
      t.bigint :storage_bytes, default: 0
      t.datetime :last_indexed_at
      t.datetime :last_queried_at

      t.timestamps
    end

    add_index :ai_knowledge_bases, [:account_id, :name], unique: true
    add_index :ai_knowledge_bases, :status
    add_index :ai_knowledge_bases, :is_public

    # ==========================================================================
    # DOCUMENTS - Source documents in knowledge bases
    # ==========================================================================
    create_table :ai_documents, id: :uuid do |t|
      t.references :knowledge_base, null: false, foreign_key: { to_table: :ai_knowledge_bases }, type: :uuid
      t.references :uploaded_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false
      t.string :source_type, null: false
      t.string :source_url
      t.string :content_type
      t.string :status, null: false, default: "pending"
      t.text :content
      t.bigint :content_size_bytes
      t.integer :chunk_count, default: 0
      t.bigint :token_count, default: 0
      t.string :checksum
      t.jsonb :metadata, default: {}
      t.jsonb :extraction_config, default: {}
      t.jsonb :processing_errors, default: []
      t.datetime :processed_at
      t.datetime :last_refreshed_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :ai_documents, [:knowledge_base_id, :status]
    add_index :ai_documents, [:knowledge_base_id, :name]
    add_index :ai_documents, :source_type
    add_index :ai_documents, :checksum

    # ==========================================================================
    # DOCUMENT CHUNKS - Chunked content with embeddings
    # ==========================================================================
    create_table :ai_document_chunks, id: :uuid do |t|
      t.references :document, null: false, foreign_key: { to_table: :ai_documents }, type: :uuid
      t.references :knowledge_base, null: false, foreign_key: { to_table: :ai_knowledge_bases }, type: :uuid
      t.integer :sequence_number, null: false
      t.text :content, null: false
      t.integer :token_count
      t.integer :start_offset
      t.integer :end_offset
      t.jsonb :embedding, default: []
      t.string :embedding_model
      t.jsonb :metadata, default: {}
      t.float :relevance_score
      t.datetime :embedded_at

      t.timestamps
    end

    add_index :ai_document_chunks, [:document_id, :sequence_number], unique: true
    add_index :ai_document_chunks, [:knowledge_base_id, :created_at]

    # ==========================================================================
    # RAG QUERIES - Query history and analytics
    # ==========================================================================
    create_table :ai_rag_queries, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :knowledge_base, null: false, foreign_key: { to_table: :ai_knowledge_bases }, type: :uuid
      t.references :user, foreign_key: true, type: :uuid
      t.uuid :workflow_run_id
      t.uuid :agent_execution_id
      t.text :query_text, null: false
      t.jsonb :query_embedding, default: []
      t.string :retrieval_strategy, default: "similarity"
      t.integer :top_k, default: 5
      t.float :similarity_threshold, default: 0.7
      t.jsonb :filters, default: {}
      t.jsonb :retrieved_chunks, default: []
      t.integer :chunks_retrieved, default: 0
      t.integer :tokens_used, default: 0
      t.float :avg_similarity_score
      t.float :query_latency_ms
      t.string :status, null: false, default: "completed"
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :ai_rag_queries, [:account_id, :created_at]
    add_index :ai_rag_queries, [:knowledge_base_id, :created_at]
    add_index :ai_rag_queries, :status

    # ==========================================================================
    # DATA CONNECTORS - External data source connections
    # ==========================================================================
    create_table :ai_data_connectors, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :knowledge_base, null: false, foreign_key: { to_table: :ai_knowledge_bases }, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false
      t.string :connector_type, null: false
      t.string :status, null: false, default: "active"
      t.jsonb :connection_config, default: {}
      t.jsonb :sync_config, default: {}
      t.string :sync_frequency
      t.datetime :last_sync_at
      t.datetime :next_sync_at
      t.integer :documents_synced, default: 0
      t.integer :sync_errors, default: 0
      t.jsonb :last_sync_result, default: {}

      t.timestamps
    end

    add_index :ai_data_connectors, [:account_id, :connector_type]
    add_index :ai_data_connectors, [:knowledge_base_id, :status]
    add_index :ai_data_connectors, :next_sync_at

    # ==========================================================================
    # CONSTRAINTS
    # ==========================================================================
    execute <<-SQL
      ALTER TABLE ai_knowledge_bases
      ADD CONSTRAINT check_kb_status
      CHECK (status IN ('active', 'indexing', 'paused', 'archived', 'error'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_knowledge_bases
      ADD CONSTRAINT check_kb_chunking_strategy
      CHECK (chunking_strategy IN ('recursive', 'semantic', 'fixed', 'sentence', 'paragraph', 'custom'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_documents
      ADD CONSTRAINT check_document_status
      CHECK (status IN ('pending', 'processing', 'indexed', 'failed', 'archived'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_documents
      ADD CONSTRAINT check_document_source_type
      CHECK (source_type IN ('upload', 'url', 'api', 'database', 'cloud_storage', 'git'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_rag_queries
      ADD CONSTRAINT check_rag_query_status
      CHECK (status IN ('pending', 'processing', 'completed', 'failed'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_data_connectors
      ADD CONSTRAINT check_connector_type
      CHECK (connector_type IN ('notion', 'confluence', 'google_drive', 'dropbox', 'github', 's3', 'database', 'api', 'web_scraper'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_data_connectors
      ADD CONSTRAINT check_connector_status
      CHECK (status IN ('active', 'paused', 'error', 'disconnected'))
    SQL
  end
end

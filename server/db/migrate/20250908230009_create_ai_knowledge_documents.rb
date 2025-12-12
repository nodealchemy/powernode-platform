# frozen_string_literal: true

class CreateAiKnowledgeDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_knowledge_documents, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.uuid :user_id, null: false
      t.uuid :knowledge_base_article_id
      t.uuid :page_id
      t.string :document_type, null: false, limit: 50
      t.string :title, null: false, limit: 500
      t.text :content, null: false
      t.text :summary
      t.jsonb :metadata, default: {}
      t.string :source_url, limit: 1000
      t.string :content_hash, limit: 64
      t.integer :chunk_size, default: 0
      t.integer :chunk_overlap, default: 0
      t.jsonb :chunked_content, default: []
      t.text :embedding_data
      t.string :embedding_model, limit: 100
      t.string :status, default: 'pending', limit: 20
      t.timestamp :processed_at
      t.timestamp :indexed_at
      t.timestamps

      t.index :account_id
      t.index :user_id
      t.index :knowledge_base_article_id
      t.index :page_id
      t.index :document_type
      t.index :content_hash
      t.index :status
      t.index :processed_at
      t.index :indexed_at
      t.index [ :account_id, :document_type ]
      t.index [ :account_id, :status ]

      t.foreign_key :accounts, on_delete: :cascade
      t.foreign_key :users, on_delete: :restrict
      t.foreign_key :knowledge_base_articles, on_delete: :cascade
      t.foreign_key :pages, on_delete: :cascade
    end

    # Vector indexing will be added later when pgvector is properly configured
    add_index :ai_knowledge_documents, :chunked_content, using: 'gin'
  end
end

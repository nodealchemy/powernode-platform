# frozen_string_literal: true

class CreateAiSearchIndices < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_search_indices, id: :uuid do |t|
      t.uuid :account_id, null: false
      t.string :index_name, null: false, limit: 100
      t.string :index_type, null: false, limit: 50
      t.text :description
      t.jsonb :configuration, default: {}
      t.integer :document_count, default: 0
      t.integer :total_chunks, default: 0
      t.string :embedding_model, limit: 100
      t.integer :embedding_dimensions, default: 1536
      t.string :status, default: 'active', limit: 20
      t.jsonb :metadata, default: {}
      t.timestamp :last_updated_at
      t.timestamp :last_indexed_at
      t.timestamps

      t.index :account_id
      t.index :index_name, unique: true
      t.index :index_type
      t.index :status
      t.index :last_updated_at
      t.index :last_indexed_at
      t.index [ :account_id, :index_type ]

      t.foreign_key :accounts, on_delete: :cascade
    end
  end
end

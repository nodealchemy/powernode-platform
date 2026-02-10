# frozen_string_literal: true

class CreateAiHybridSearchResults < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_hybrid_search_results, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.text :query_text, null: false
      t.string :search_mode, null: false
      t.jsonb :vector_results, default: []
      t.jsonb :keyword_results, default: []
      t.jsonb :graph_results, default: []
      t.jsonb :merged_results, default: []
      t.integer :result_count, default: 0
      t.decimal :vector_score, precision: 5, scale: 4
      t.decimal :keyword_score, precision: 5, scale: 4
      t.decimal :graph_score, precision: 5, scale: 4
      t.string :fusion_method, default: "rrf"
      t.boolean :reranked, default: false
      t.string :rerank_model
      t.integer :total_latency_ms
      t.jsonb :metadata, default: {}

      t.datetime :created_at, null: false
    end

    # Check constraint for search_mode
    execute <<~SQL
      ALTER TABLE ai_hybrid_search_results
      ADD CONSTRAINT check_ai_hybrid_search_mode
      CHECK (search_mode IN ('vector', 'keyword', 'hybrid', 'graph'))
    SQL

    add_index :ai_hybrid_search_results, :search_mode
    add_index :ai_hybrid_search_results, :created_at
  end
end

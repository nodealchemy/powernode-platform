# frozen_string_literal: true

class CreateAiKnowledgeGraphNodes < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_knowledge_graph_nodes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :knowledge_base, type: :uuid, null: true, foreign_key: { to_table: :ai_knowledge_bases }, index: true
      t.string :name, null: false
      t.string :node_type, null: false
      t.string :entity_type
      t.text :description
      t.jsonb :properties, default: {}
      t.column :path, :ltree
      t.references :source_document, type: :uuid, null: true, foreign_key: { to_table: :ai_documents }, index: false
      t.decimal :confidence, precision: 5, scale: 4, default: 1.0
      t.integer :mention_count, default: 1
      t.datetime :last_seen_at
      t.string :status, default: "active"
      t.references :merged_into, type: :uuid, null: true, foreign_key: { to_table: :ai_knowledge_graph_nodes }, index: false
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # pgvector embedding column
    execute "ALTER TABLE ai_knowledge_graph_nodes ADD COLUMN embedding vector(1536)"

    # HNSW index for cosine distance
    execute <<~SQL
      CREATE INDEX index_ai_knowledge_graph_nodes_on_embedding
      ON ai_knowledge_graph_nodes
      USING hnsw (embedding vector_cosine_ops)
    SQL

    # Additional indexes
    add_index :ai_knowledge_graph_nodes, :node_type
    add_index :ai_knowledge_graph_nodes, :entity_type
    add_index :ai_knowledge_graph_nodes, :name, name: "index_ai_kg_nodes_on_name"
    add_index :ai_knowledge_graph_nodes, :path, using: :gist
    add_index :ai_knowledge_graph_nodes, :status
    add_index :ai_knowledge_graph_nodes, [:account_id, :name, :node_type],
              unique: true,
              where: "status = 'active'",
              name: "index_ai_kg_nodes_unique_active"

    # Check constraints
    execute <<~SQL
      ALTER TABLE ai_knowledge_graph_nodes
      ADD CONSTRAINT check_ai_kg_node_type
      CHECK (node_type IN ('entity', 'concept', 'relation', 'attribute'))
    SQL

    execute <<~SQL
      ALTER TABLE ai_knowledge_graph_nodes
      ADD CONSTRAINT check_ai_kg_node_status
      CHECK (status IN ('active', 'merged', 'archived'))
    SQL
  end
end

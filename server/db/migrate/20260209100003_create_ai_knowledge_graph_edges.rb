# frozen_string_literal: true

class CreateAiKnowledgeGraphEdges < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_knowledge_graph_edges, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :source_node, type: :uuid, null: false, foreign_key: { to_table: :ai_knowledge_graph_nodes }, index: true
      t.references :target_node, type: :uuid, null: false, foreign_key: { to_table: :ai_knowledge_graph_nodes }, index: true
      t.string :relation_type, null: false
      t.string :label
      t.decimal :weight, precision: 5, scale: 4, default: 1.0
      t.decimal :confidence, precision: 5, scale: 4, default: 1.0
      t.jsonb :properties, default: {}
      t.references :source_document, type: :uuid, null: true, foreign_key: { to_table: :ai_documents }, index: false
      t.boolean :bidirectional, default: false
      t.string :status, default: "active"
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # Unique constraint on edges
    add_index :ai_knowledge_graph_edges, [:source_node_id, :target_node_id, :relation_type],
              unique: true,
              where: "status = 'active'",
              name: "index_ai_kg_edges_unique_active"

    add_index :ai_knowledge_graph_edges, :relation_type
  end
end

# frozen_string_literal: true

class ExtendKnowledgeGraphForCodebase < ActiveRecord::Migration[8.0]
  def up
    # 1. Extend node_type CHECK constraint to include 'code_entity'
    execute <<~SQL
      ALTER TABLE ai_knowledge_graph_nodes
      DROP CONSTRAINT IF EXISTS check_ai_kg_node_type
    SQL

    execute <<~SQL
      ALTER TABLE ai_knowledge_graph_nodes
      ADD CONSTRAINT check_ai_kg_node_type
      CHECK (node_type IN ('entity', 'concept', 'relation', 'attribute', 'code_entity'))
    SQL

    # 2. Add git_repository_id to knowledge_bases for project scoping
    unless column_exists?(:ai_knowledge_bases, :git_repository_id)
      add_reference :ai_knowledge_bases, :git_repository,
                    type: :uuid,
                    foreign_key: { to_table: :git_repositories },
                    null: true,
                    index: true
    end

    # 3. Composite index for code entity lookups
    unless index_exists?(:ai_knowledge_graph_nodes, [:account_id, :entity_type, :knowledge_base_id], name: "idx_kg_nodes_code_entities")
      add_index :ai_knowledge_graph_nodes,
                [:account_id, :entity_type, :knowledge_base_id],
                where: "node_type = 'code_entity' AND status = 'active'",
                name: "idx_kg_nodes_code_entities"
    end

    # 4. GIN index on metadata for file mtime queries during incremental indexing
    unless index_exists?(:ai_knowledge_graph_nodes, :metadata, name: "idx_kg_nodes_code_metadata")
      add_index :ai_knowledge_graph_nodes, :metadata,
                using: :gin,
                where: "node_type = 'code_entity'",
                name: "idx_kg_nodes_code_metadata"
    end
  end

  def down
    remove_index :ai_knowledge_graph_nodes, name: "idx_kg_nodes_code_metadata", if_exists: true
    remove_index :ai_knowledge_graph_nodes, name: "idx_kg_nodes_code_entities", if_exists: true

    if column_exists?(:ai_knowledge_bases, :git_repository_id)
      remove_reference :ai_knowledge_bases, :git_repository
    end

    execute <<~SQL
      ALTER TABLE ai_knowledge_graph_nodes
      DROP CONSTRAINT IF EXISTS check_ai_kg_node_type
    SQL

    execute <<~SQL
      ALTER TABLE ai_knowledge_graph_nodes
      ADD CONSTRAINT check_ai_kg_node_type
      CHECK (node_type IN ('entity', 'concept', 'relation', 'attribute'))
    SQL
  end
end

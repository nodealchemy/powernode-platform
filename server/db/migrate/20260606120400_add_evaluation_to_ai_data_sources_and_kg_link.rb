# frozen_string_literal: true

class AddEvaluationToAiDataSourcesAndKgLink < ActiveRecord::Migration[8.0]
  def change
    # Evaluation / scoring foundation on ai_data_sources.
    add_column :ai_data_sources, :effectiveness_score, :decimal, precision: 5, scale: 4, default: 0.5
    add_column :ai_data_sources, :usage_count, :integer, null: false, default: 0
    add_column :ai_data_sources, :positive_usage_count, :integer, null: false, default: 0
    add_column :ai_data_sources, :negative_usage_count, :integer, null: false, default: 0
    add_column :ai_data_sources, :last_used_at, :datetime

    # Knowledge-graph link from a node back to its data source. Nullable
    # standalone column (NOT a t.references) on the large knowledge_graph_nodes
    # table — a single partial index covers the only lookup pattern
    # (entity_type = "data_source" nodes), avoiding write amplification on
    # the overwhelming majority of rows where ai_data_source_id IS NULL.
    add_column :ai_knowledge_graph_nodes, :ai_data_source_id, :uuid
    add_index :ai_knowledge_graph_nodes, :ai_data_source_id,
              where: "ai_data_source_id IS NOT NULL",
              name: "index_ai_kg_nodes_on_ai_data_source_id"
  end
end

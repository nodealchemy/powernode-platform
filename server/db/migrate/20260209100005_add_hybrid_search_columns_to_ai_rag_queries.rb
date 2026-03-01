# frozen_string_literal: true

class AddHybridSearchColumnsToAiRagQueries < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_rag_queries, :search_mode, :string, default: "vector"
    add_column :ai_rag_queries, :graph_depth, :integer, default: 2
    add_column :ai_rag_queries, :enable_reranking, :boolean, default: false
  end
end

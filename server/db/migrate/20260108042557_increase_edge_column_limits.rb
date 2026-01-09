# frozen_string_literal: true

class IncreaseEdgeColumnLimits < ActiveRecord::Migration[8.0]
  def change
    # Increase edge_id limit from 100 to 255 characters to accommodate
    # React Flow generated edge IDs which include source/target node IDs + timestamps
    change_column :ai_workflow_edges, :edge_id, :string, limit: 255, null: false

    # Also increase source/target node ID limits for consistency with ai_workflow_nodes
    change_column :ai_workflow_edges, :source_node_id, :string, limit: 255, null: false
    change_column :ai_workflow_edges, :target_node_id, :string, limit: 255, null: false
  end
end

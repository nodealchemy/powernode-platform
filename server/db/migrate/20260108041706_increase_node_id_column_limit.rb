# frozen_string_literal: true

class IncreaseNodeIdColumnLimit < ActiveRecord::Migration[8.0]
  def change
    # Increase node_id limit from 100 to 255 characters to accommodate
    # longer React Flow generated node IDs (e.g., UUID format IDs)
    change_column :ai_workflow_nodes, :node_id, :string, limit: 255, null: false

    # Also increase error_node_id limit for consistency
    change_column :ai_workflow_nodes, :error_node_id, :string, limit: 255
  end
end

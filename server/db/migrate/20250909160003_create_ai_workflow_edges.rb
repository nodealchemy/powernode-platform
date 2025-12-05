# frozen_string_literal: true

class CreateAiWorkflowEdges < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_workflow_edges, id: :uuid do |t|
      t.references :ai_workflow, null: false, foreign_key: true, type: :uuid
      t.string :edge_id, null: false, limit: 100
      t.string :source_node_id, null: false, limit: 100
      t.string :target_node_id, null: false, limit: 100
      t.string :source_handle, limit: 50
      t.string :target_handle, limit: 50
      t.string :edge_type, null: false, default: 'default'
      t.jsonb :condition, null: false, default: {}
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.boolean :is_conditional, null: false, default: false
      t.integer :priority, null: false, default: 0
      t.timestamps

      t.index [:ai_workflow_id, :edge_id], unique: true, name: 'index_workflow_edges_on_workflow_edge_id'
      t.index [:ai_workflow_id, :source_node_id]
      t.index [:ai_workflow_id, :target_node_id]
      t.index [:ai_workflow_id, :is_conditional]
      t.index :priority
    end

    add_check_constraint :ai_workflow_edges,
      "edge_type IN ('default', 'success', 'error', 'conditional', 'loop')",
      name: 'ai_workflow_edges_type_check'

    # Note: Foreign key constraints will be validated at the application level
    # since we're using node_id (not the primary key) for relationships
  end
end
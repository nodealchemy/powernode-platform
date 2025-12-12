# frozen_string_literal: true

class CreateAiWorkflowNodes < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_workflow_nodes, id: :uuid do |t|
      t.references :ai_workflow, null: false, foreign_key: true, type: :uuid
      t.string :node_id, null: false, limit: 100
      t.string :node_type, null: false, limit: 50
      t.string :name, null: false, limit: 255
      t.text :description
      t.jsonb :position, null: false, default: {}
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :validation_rules, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.boolean :is_start_node, null: false, default: false
      t.boolean :is_end_node, null: false, default: false
      t.boolean :is_error_handler, null: false, default: false
      t.string :error_node_id, limit: 100
      t.integer :timeout_seconds, default: 300
      t.integer :retry_count, default: 0
      t.timestamps

      t.index [ :ai_workflow_id, :node_id ], unique: true, name: 'index_workflow_nodes_on_workflow_node_id'
      t.index [ :ai_workflow_id, :node_type ]
      t.index [ :ai_workflow_id, :is_start_node ]
      t.index [ :ai_workflow_id, :is_end_node ]
      t.index :node_id
    end

    add_check_constraint :ai_workflow_nodes,
      "node_type IN ('ai_agent', 'api_call', 'webhook', 'condition', 'loop', 'transform', 'delay', 'human_approval', 'sub_workflow', 'merge', 'split')",
      name: 'ai_workflow_nodes_type_check'

    add_check_constraint :ai_workflow_nodes,
      "timeout_seconds > 0",
      name: 'ai_workflow_nodes_timeout_check'

    add_check_constraint :ai_workflow_nodes,
      "retry_count >= 0",
      name: 'ai_workflow_nodes_retry_check'
  end
end

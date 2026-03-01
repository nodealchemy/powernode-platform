# frozen_string_literal: true

class AddA2aEnhancements < ActiveRecord::Migration[8.0]
  def change
    # Add DAG execution fields to A2A tasks
    add_column :ai_a2a_tasks, :dag_node_id, :string
    add_column :ai_a2a_tasks, :dag_execution_id, :uuid
    add_column :ai_a2a_tasks, :dag_dependencies, :jsonb, default: []
    add_column :ai_a2a_tasks, :dag_dependents, :jsonb, default: []
    add_column :ai_a2a_tasks, :execution_order, :integer

    add_index :ai_a2a_tasks, :dag_execution_id, where: "dag_execution_id IS NOT NULL"
    add_index :ai_a2a_tasks, [ :dag_execution_id, :execution_order ], where: "dag_execution_id IS NOT NULL"

    # Add chat gateway integration to A2A tasks
    add_column :ai_a2a_tasks, :chat_session_id, :uuid
    add_column :ai_a2a_tasks, :chat_message_id, :uuid

    add_foreign_key :ai_a2a_tasks, :chat_sessions, column: :chat_session_id, on_delete: :nullify
    add_foreign_key :ai_a2a_tasks, :chat_messages, column: :chat_message_id, on_delete: :nullify

    # Add container execution reference
    add_column :ai_a2a_tasks, :container_instance_id, :uuid
    add_foreign_key :ai_a2a_tasks, :mcp_container_instances, column: :container_instance_id, on_delete: :nullify

    # Create DAG executions table for multi-agent workflows
    create_table :ai_dag_executions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid, index: true
      t.references :workflow, foreign_key: { to_table: :ai_workflows }, type: :uuid, index: true
      t.references :triggered_by, foreign_key: { to_table: :users }, type: :uuid

      t.string :name
      t.string :status, default: "pending"  # pending, running, completed, failed, cancelled
      t.jsonb :dag_definition, default: {}  # Node definitions and edges
      t.jsonb :execution_plan, default: []  # Ordered execution steps
      t.jsonb :node_states, default: {}  # State of each node
      t.jsonb :shared_context, default: {}  # Context passed between nodes
      t.jsonb :final_outputs, default: {}  # Aggregated outputs

      t.integer :total_nodes, default: 0
      t.integer :completed_nodes, default: 0
      t.integer :failed_nodes, default: 0
      t.integer :running_nodes, default: 0

      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      t.text :error_message

      # Checkpointing for resume
      t.jsonb :checkpoint_data, default: {}
      t.datetime :last_checkpoint_at
      t.boolean :resumable, default: true

      t.timestamps
    end

    add_index :ai_dag_executions, :status
    add_index :ai_dag_executions, [ :account_id, :status ]

    add_check_constraint :ai_dag_executions, "status IN ('pending', 'running', 'completed', 'failed', 'cancelled')", name: "ai_dag_executions_status_check"

    # Add capabilities to agent cards
    add_column :ai_agent_cards, :community_published, :boolean, default: false
    add_column :ai_agent_cards, :federation_enabled, :boolean, default: false
    add_column :ai_agent_cards, :container_execution, :boolean, default: false
    add_column :ai_agent_cards, :chat_gateway_enabled, :boolean, default: false
  end
end

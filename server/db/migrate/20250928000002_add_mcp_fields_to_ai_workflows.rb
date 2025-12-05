# frozen_string_literal: true

class AddMcpFieldsToAiWorkflows < ActiveRecord::Migration[7.1]
  def change
    # Add MCP orchestration configuration to ai_workflows
    add_column :ai_workflows, :mcp_orchestration_config, :jsonb, null: false, default: {}
    add_column :ai_workflows, :mcp_tool_requirements, :jsonb, null: false, default: []
    add_column :ai_workflows, :mcp_input_schema, :jsonb, null: false, default: {}
    add_column :ai_workflows, :mcp_output_schema, :jsonb, null: false, default: {}

    # Add MCP configuration to ai_workflow_nodes
    add_column :ai_workflow_nodes, :mcp_tool_config, :jsonb, null: false, default: {}
    add_column :ai_workflow_nodes, :mcp_tool_id, :string
    add_column :ai_workflow_nodes, :mcp_tool_version, :string

    # Add MCP execution context to ai_workflow_runs
    add_column :ai_workflow_runs, :mcp_execution_context, :jsonb, null: false, default: {}

    # Add indexes for MCP queries
    add_index :ai_workflows, :mcp_tool_requirements, using: :gin
    add_index :ai_workflow_nodes, :mcp_tool_id
    add_index :ai_workflow_nodes, [:mcp_tool_id, :mcp_tool_version], name: 'index_workflow_nodes_on_mcp_tool_and_version'

    # Add comments to document MCP fields
    execute <<-SQL
      COMMENT ON COLUMN ai_workflows.mcp_orchestration_config IS 'MCP-specific orchestration configuration';
      COMMENT ON COLUMN ai_workflows.mcp_tool_requirements IS 'Array of required MCP tools for workflow execution';
      COMMENT ON COLUMN ai_workflow_nodes.mcp_tool_config IS 'MCP tool configuration for this node';
      COMMENT ON COLUMN ai_workflow_nodes.mcp_tool_id IS 'ID of the MCP tool used by this node';
      COMMENT ON COLUMN ai_workflow_runs.mcp_execution_context IS 'MCP execution context and state';
    SQL
  end

  def down
    # Remove MCP-specific fields
    remove_column :ai_workflows, :mcp_orchestration_config
    remove_column :ai_workflows, :mcp_tool_requirements
    remove_column :ai_workflows, :mcp_input_schema
    remove_column :ai_workflows, :mcp_output_schema

    remove_column :ai_workflow_nodes, :mcp_tool_config
    remove_column :ai_workflow_nodes, :mcp_tool_id
    remove_column :ai_workflow_nodes, :mcp_tool_version

    remove_column :ai_workflow_runs, :mcp_execution_context

    # Remove indexes
    remove_index :ai_workflow_nodes, name: 'index_workflow_nodes_on_mcp_tool_and_version' if index_exists?(:ai_workflow_nodes, [:mcp_tool_id, :mcp_tool_version], name: 'index_workflow_nodes_on_mcp_tool_and_version')
  end
end
# frozen_string_literal: true

class AddMcpFieldsToAiAgents < ActiveRecord::Migration[7.1]
  def change
    # Add MCP-specific fields to ai_agents table
    add_column :ai_agents, :mcp_tool_manifest, :jsonb, null: false, default: {}
    add_column :ai_agents, :mcp_input_schema, :jsonb, null: false, default: {}
    add_column :ai_agents, :mcp_output_schema, :jsonb, null: false, default: {}
    add_column :ai_agents, :mcp_capabilities, :jsonb, null: false, default: []
    add_column :ai_agents, :mcp_metadata, :jsonb, null: false, default: {}
    add_column :ai_agents, :mcp_registered_at, :timestamp

    # Update version field to support semantic versioning
    change_column_default :ai_agents, :version, '1.0.0'

    # Add indexes for MCP-specific queries
    add_index :ai_agents, :mcp_registered_at
    add_index :ai_agents, [ :account_id, :status ], name: 'index_ai_agents_on_account_and_status'

    # GIN indexes for JSONB fields for better query performance
    add_index :ai_agents, :mcp_capabilities, using: :gin
    add_index :ai_agents, :mcp_tool_manifest, using: :gin

    # Remove legacy fields that are no longer needed in MCP-only implementation
    # Note: We're keeping these for now to allow for gradual migration
    # They will be removed in a future migration after full MCP conversion

    # Add comment to document the MCP transformation
    execute <<-SQL
      COMMENT ON COLUMN ai_agents.mcp_tool_manifest IS 'Complete MCP tool manifest for agent registration';
      COMMENT ON COLUMN ai_agents.mcp_input_schema IS 'JSON Schema for validating agent input parameters';
      COMMENT ON COLUMN ai_agents.mcp_output_schema IS 'JSON Schema for validating agent output';
      COMMENT ON COLUMN ai_agents.mcp_capabilities IS 'Array of MCP capabilities supported by this agent';
      COMMENT ON COLUMN ai_agents.mcp_metadata IS 'Additional MCP-specific metadata';
    SQL
  end

  def down
    # Remove MCP-specific fields
    remove_column :ai_agents, :mcp_tool_manifest
    remove_column :ai_agents, :mcp_input_schema
    remove_column :ai_agents, :mcp_output_schema
    remove_column :ai_agents, :mcp_capabilities
    remove_column :ai_agents, :mcp_metadata
    remove_column :ai_agents, :mcp_registered_at

    # Remove indexes
    remove_index :ai_agents, name: 'index_ai_agents_on_account_and_status' if index_exists?(:ai_agents, [ :account_id, :status ], name: 'index_ai_agents_on_account_and_status')

    # Revert version field default
    change_column_default :ai_agents, :version, nil
  end
end

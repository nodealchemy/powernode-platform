# frozen_string_literal: true

class DropMcpCapabilitiesFromAiAgents < ActiveRecord::Migration[8.0]
  def change
    remove_index :ai_agents, :mcp_capabilities, if_exists: true
    remove_column :ai_agents, :mcp_capabilities, :jsonb, default: [], null: false
  end
end

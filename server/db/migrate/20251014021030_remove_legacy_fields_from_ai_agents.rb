# frozen_string_literal: true

class RemoveLegacyFieldsFromAiAgents < ActiveRecord::Migration[8.0]
  def up
    Rails.logger.info "Migrating legacy agent configuration data to MCP fields..."

    # Migrate any remaining data from old columns to MCP fields
    AiAgent.find_each do |agent|
      needs_save = false

      # Migrate capabilities if MCP capabilities is empty but old capabilities exists
      if agent.mcp_capabilities.blank? && agent.read_attribute(:capabilities).present?
        agent.mcp_capabilities = agent.read_attribute(:capabilities)
        needs_save = true
        Rails.logger.info "Migrated capabilities for agent #{agent.slug}"
      end

      # Migrate configuration to mcp_tool_manifest if needed
      if agent.read_attribute(:configuration).present?
        old_config = agent.read_attribute(:configuration)
        if old_config.is_a?(Hash) && old_config.any?
          # Merge old configuration into mcp_tool_manifest
          agent.mcp_tool_manifest = (agent.mcp_tool_manifest || {}).merge(old_config)
          needs_save = true
          Rails.logger.info "Migrated configuration for agent #{agent.slug}"
        end
      end

      agent.save! if needs_save
    end

    Rails.logger.info "Data migration complete. Removing legacy columns..."

    # Remove the old columns
    remove_column :ai_agents, :configuration, :jsonb if column_exists?(:ai_agents, :configuration)
    remove_column :ai_agents, :capabilities, :jsonb if column_exists?(:ai_agents, :capabilities)

    Rails.logger.info "Legacy columns removed successfully."
  end

  def down
    Rails.logger.info "Restoring legacy columns..."

    # Restore the old columns
    add_column :ai_agents, :configuration, :jsonb, default: {}, null: false
    add_column :ai_agents, :capabilities, :jsonb, default: [], null: false

    # Copy MCP data back to legacy columns for rollback
    AiAgent.find_each do |agent|
      agent.update_columns(
        capabilities: agent.mcp_capabilities || [],
        configuration: agent.mcp_tool_manifest || {}
      )
    end

    Rails.logger.info "Legacy columns restored."
  end
end

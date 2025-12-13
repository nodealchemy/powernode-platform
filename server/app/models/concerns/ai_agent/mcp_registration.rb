# frozen_string_literal: true

module AiAgent::McpRegistration
  extend ActiveSupport::Concern

  included do
    after_create :register_mcp_tool
    after_update :update_mcp_tool_registration, if: :saved_change_to_mcp_tool_manifest?
    after_destroy :unregister_mcp_tool
  end

  # Register agent as MCP tool (public method for manual registration)
  def register_as_mcp_tool
    Rails.logger.info "[AI_AGENT_MCP] Registering agent #{id} as MCP tool"

    mcp_registry = McpRegistryService.new(account: account)
    tool_manifest = generate_mcp_tool_manifest

    mcp_registry.register_tool(mcp_tool_id, tool_manifest)

    # Update agent with registration info
    update!(
      mcp_tool_manifest: tool_manifest,
      mcp_registered_at: Time.current
    )

    Rails.logger.info "[AI_AGENT_MCP] Agent registered with tool ID: #{mcp_tool_id}"
    mcp_tool_id
  end

  # Unregister agent from MCP registry (public method for manual unregistration)
  def unregister_from_mcp
    Rails.logger.info "[AI_AGENT_MCP] Unregistering agent #{id} from MCP"

    mcp_registry = McpRegistryService.new(account: account)
    mcp_registry.unregister_tool(mcp_tool_id)

    Rails.logger.info "[AI_AGENT_MCP] Agent unregistered from MCP"
  end

  private

  def register_mcp_tool
    return unless mcp_available?

    begin
      registry = McpRegistryService.new(account: account)
      tool_id = mcp_tool_id
      manifest = mcp_tool_manifest

      registry.register_tool(tool_id, manifest)
      Rails.logger.info "[AI_AGENT_MCP] Registered agent #{id} as MCP tool: #{tool_id}"
    rescue StandardError => e
      Rails.logger.error "[AI_AGENT_MCP] Failed to register MCP tool: #{e.message}"
      # Don't fail the creation, but log the error
    end
  end

  def update_mcp_tool_registration
    return unless mcp_available?

    begin
      registry = McpRegistryService.new(account: account)
      tool_id = mcp_tool_id
      manifest = mcp_tool_manifest

      registry.update_tool(tool_id, manifest)
      Rails.logger.info "[AI_AGENT_MCP] Updated MCP tool registration for agent #{id}: #{tool_id}"
    rescue StandardError => e
      Rails.logger.error "[AI_AGENT_MCP] Failed to update MCP tool registration: #{e.message}"
    end
  end

  def unregister_mcp_tool
    begin
      registry = McpRegistryService.new(account: account)
      tool_id = mcp_tool_id

      registry.unregister_tool(tool_id)
      Rails.logger.info "[AI_AGENT_MCP] Unregistered MCP tool for agent #{id}: #{tool_id}"
    rescue StandardError => e
      Rails.logger.error "[AI_AGENT_MCP] Failed to unregister MCP tool: #{e.message}"
      # Don't fail the destruction, but log the error
    end
  end
end

# frozen_string_literal: true

module Ai
  class Agent
    module McpTool
      extend ActiveSupport::Concern

      # Check if agent is available for MCP execution
      def mcp_available?
        active? && mcp_tool_manifest.present? && mcp_capabilities.any? && provider&.is_active?
      end

      # Get MCP tool ID for registry
      def mcp_tool_id
        "agent_#{id}_v#{version.gsub('.', '_')}"
      end

      # Get MCP tool name (used for tool registration)
      def mcp_tool_name
        "#{account.subdomain}_#{slug}".downcase.gsub(/[^a-z0-9_]/, "_")
      end

      # Generate complete MCP tool manifest
      def generate_mcp_tool_manifest
        {
          "name" => mcp_tool_name,
          "description" => description || "AI Agent: #{name}",
          "type" => "ai_agent",
          "version" => version,
          "capabilities" => mcp_capabilities,
          "inputSchema" => mcp_input_schema.presence || default_input_schema,
          "outputSchema" => mcp_output_schema.presence || default_output_schema,
          "metadata" => generate_mcp_metadata,
          "agent_id" => id,
          "provider_id" => ai_provider_id,
          "account_id" => account_id,
          "creator_id" => creator_id,
          "agent_type" => agent_type,
          "created_at" => created_at&.iso8601,
          "updated_at" => updated_at&.iso8601
        }
      end

      # Check if agent supports a specific MCP capability
      def supports_mcp_capability?(capability)
        mcp_capabilities.include?(capability.to_s)
      end

      # Get agent performance metrics via MCP telemetry
      def mcp_performance_metrics
        telemetry = Mcp::TelemetryService.new(account: account)
        telemetry.get_tool_performance(mcp_tool_id)
      end

      private

      def generate_mcp_metadata
        {
          "powernode_agent_id" => id,
          "powernode_account_id" => account_id,
          "powernode_creator_id" => creator_id,
          "agent_type" => agent_type,
          "provider_type" => provider&.provider_type,
          "tags" => [],
          "documentation_url" => nil,
          "support_url" => nil,
          "license" => "proprietary"
        }
      end

      def has_required_manifest_fields?
        return false unless mcp_tool_manifest.is_a?(Hash)
        required_fields = %w[name description type version]
        required_fields.all? { |field| mcp_tool_manifest[field].present? }
      end
    end
  end
end

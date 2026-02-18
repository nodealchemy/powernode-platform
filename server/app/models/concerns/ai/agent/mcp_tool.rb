# frozen_string_literal: true

module Ai
  class Agent
    module McpTool
      extend ActiveSupport::Concern

      # Check if agent is available for MCP execution
      def mcp_available?
        active? && mcp_tool_manifest.present? && provider&.is_active?
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
        capabilities = skill_slugs.dup

        # Expand capabilities with graph-adjacent skills (1-hop neighbors)
        begin
          if account.ai_knowledge_graph_nodes.active.skill_nodes.exists?
            graph_service = Ai::KnowledgeGraph::GraphService.new(account)
            adjacent = []
            skills.active.each do |skill|
              node = skill.knowledge_graph_node
              next unless node&.status == "active"
              neighbors = graph_service.find_neighbors(node: node, depth: 1, relation_types: %w[requires related_to])
              neighbors.each do |n|
                name = n[:name]
                adjacent << { "id" => name, "confidence" => 0.7 } if name.present? && !skill_slugs.include?(name)
              end
            end
            capabilities = skill_slugs.map { |s| { "id" => s, "confidence" => 1.0 } } + adjacent.uniq { |a| a["id"] }
          end
        rescue => e
          Rails.logger.warn "[McpTool] Graph-adjacent skill expansion failed: #{e.message}"
        end

        {
          "name" => mcp_tool_name,
          "description" => description || "AI Agent: #{name}",
          "type" => "ai_agent",
          "version" => version,
          "capabilities" => capabilities,
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
        cap_str = capability.to_s
        return true if skill_slugs.include?(cap_str)

        # Check graph-adjacent skills
        begin
          if account.ai_knowledge_graph_nodes.active.skill_nodes.exists?
            graph_service = Ai::KnowledgeGraph::GraphService.new(account)
            skills.active.each do |skill|
              node = skill.knowledge_graph_node
              next unless node&.status == "active"
              neighbors = graph_service.find_neighbors(node: node, depth: 1, relation_types: %w[requires related_to])
              names = neighbors.map { |n| n[:name] }.compact
              return true if names.include?(cap_str)
            end
          end
        rescue => e
          Rails.logger.warn "[McpTool] Graph-adjacent capability check failed: #{e.message}"
        end

        false
      end

      # =============================================================================
      # MODEL CONFIGURATION - Single Source of Truth
      # =============================================================================
      # The canonical location for model config is mcp_metadata.model_config
      # These accessors provide a clean interface for reading/writing model settings

      def model
        mcp_metadata&.dig("model_config", "model")
      end

      def model=(value)
        self.mcp_metadata ||= {}
        self.mcp_metadata["model_config"] ||= {}
        self.mcp_metadata["model_config"]["model"] = value
      end

      def temperature
        mcp_metadata&.dig("model_config", "temperature") || 0.7
      end

      def temperature=(value)
        self.mcp_metadata ||= {}
        self.mcp_metadata["model_config"] ||= {}
        self.mcp_metadata["model_config"]["temperature"] = value
      end

      def max_tokens
        mcp_metadata&.dig("model_config", "max_tokens") || 2048
      end

      def max_tokens=(value)
        self.mcp_metadata ||= {}
        self.mcp_metadata["model_config"] ||= {}
        self.mcp_metadata["model_config"]["max_tokens"] = value
      end

      def system_prompt
        mcp_metadata&.dig("model_config", "system_prompt")
      end

      def system_prompt=(value)
        self.mcp_metadata ||= {}
        self.mcp_metadata["model_config"] ||= {}
        self.mcp_metadata["model_config"]["system_prompt"] = value
      end

      def model_config
        mcp_metadata&.dig("model_config") || {}
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

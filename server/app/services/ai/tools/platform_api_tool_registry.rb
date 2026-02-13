# frozen_string_literal: true

module Ai
  module Tools
    class PlatformApiToolRegistry
      TOOLS = {
        "create_gitea_repository" => "Ai::Tools::ProjectInitTool",
        "dispatch_to_runner" => "Ai::Tools::RunnerDispatchTool",
        "create_agent" => "Ai::Tools::AgentManagementTool",
        "list_agents" => "Ai::Tools::AgentManagementTool",
        "execute_agent" => "Ai::Tools::AgentManagementTool",
        "create_team" => "Ai::Tools::TeamManagementTool",
        "add_team_member" => "Ai::Tools::TeamManagementTool",
        "execute_team" => "Ai::Tools::TeamManagementTool",
        "create_workflow" => "Ai::Tools::WorkflowManagementTool",
        "execute_workflow" => "Ai::Tools::WorkflowManagementTool",
        "trigger_pipeline" => "Ai::Tools::PipelineManagementTool",
        "list_pipelines" => "Ai::Tools::PipelineManagementTool",
        "write_shared_memory" => "Ai::Tools::MemoryTool",
        "read_shared_memory" => "Ai::Tools::MemoryTool",
        "query_knowledge_base" => "Ai::Tools::KnowledgeTool",
        "get_api_reference" => "Ai::Tools::ApiReferenceTool"
      }.freeze

      def self.available_tools(agent: nil)
        TOOLS.each_with_object({}) do |(name, class_name), hash|
          klass = class_name.constantize
          hash[name] = klass if klass.permitted?(agent: agent)
        rescue NameError => e
          Rails.logger.warn "[PlatformApiToolRegistry] Tool class not found: #{class_name} - #{e.message}"
        end
      end

      def self.find_tool(name)
        # Check static tools first
        class_name = TOOLS[name]
        if class_name
          return class_name.constantize
        end

        # Check dynamic tools
        dynamic_tool = dynamic_tools.find { |t| t[:name] == name }
        dynamic_tool[:handler_class]&.constantize if dynamic_tool
      rescue NameError
        nil
      end

      def self.tool_definitions(agent: nil)
        available_tools(agent: agent).map { |name, klass| klass.definition.merge(name: name) }
      end

      # Discover tools by natural language query (semantic search)
      def self.discover_tools(query:, account:, capabilities: nil, limit: 10)
        service = SemanticToolDiscoveryService.new(account: account)
        service.discover(query: query, capabilities: capabilities, limit: limit)
      end

      # Register a tool dynamically at runtime
      def self.register_dynamic_tool(account:, name:, description:, parameters:, handler:, metadata: {})
        SemanticToolDiscoveryService.register_dynamic_tool(
          account: account, name: name, description: description,
          parameters: parameters, handler: handler, metadata: metadata
        )
      end

      # Unregister a dynamic tool
      def self.unregister_dynamic_tool(account:, name:)
        SemanticToolDiscoveryService.unregister_dynamic_tool(account: account, name: name)
      end

      # List dynamic tools for an account
      def self.dynamic_tools(account: nil)
        return [] unless account

        Rails.cache.read("tool_discovery:#{account.id}:dynamic_tools") || []
      end
    end
  end
end

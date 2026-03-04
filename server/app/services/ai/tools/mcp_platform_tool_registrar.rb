# frozen_string_literal: true

module Ai
  module Tools
    class McpPlatformToolRegistrar
      TOOL_ID_PREFIX = "platform"

      # Maps MCP registry keys to internal tool action names where they differ.
      # Most tools use identical registry/action names; only KnowledgeGraphTool
      # uses shortened internal names (e.g. "search" instead of "search_knowledge_graph").
      ACTION_ALIASES = {
        "search_knowledge_graph" => "search",
        "reason_knowledge_graph" => "reason",
        "get_graph_node" => "get_node",
        "list_graph_nodes" => "list_nodes",
        "get_graph_neighbors" => "get_neighbors",
        "graph_statistics" => "statistics",
        "get_subgraph" => "subgraph",
        "extract_to_knowledge_graph" => "extract"
      }.freeze

      class << self
        def register_all!(account:)
          registry = ::Mcp::RegistryService.new(account: account)

          tool_classes.each do |tool_class|
            definition = tool_class.definition
            tool_id = "#{TOOL_ID_PREFIX}.#{definition[:name]}"
            manifest = build_manifest(tool_class)

            begin
              registry.register_tool(tool_id, manifest)
            rescue ::Mcp::RegistryService::ToolConflictError
              # Already registered, skip
            rescue => e
              Rails.logger.warn "[McpPlatformToolRegistrar] Failed to register #{tool_id}: #{e.message}"
            end
          end
        end

        # Sync all platform tools to the mcp_tools database table so the
        # frontend MCP browser page can display them. Also syncs introspection
        # tools from Ai::Introspection::McpToolRegistrar.
        def sync_to_database!(account:)
          mcp_server = account.mcp_servers.find_by(name: "Powernode MCP")
          unless mcp_server
            Rails.logger.warn "[McpPlatformToolRegistrar] Powernode MCP server not found for account #{account.id}"
            return 0
          end

          synced_names = Set.new

          # Sync platform tools from PlatformApiToolRegistry::TOOLS
          PlatformApiToolRegistry::TOOLS.each do |action_name, class_name|
            tool_class = class_name.constantize
            action_defs = tool_class.action_definitions
            action_def = action_defs[action_name] || {}

            description = action_def[:description] || tool_class.definition[:description]
            parameters = action_def[:parameters] || {}
            input_schema = convert_to_json_schema(parameters)
            required_permission = tool_class::REQUIRED_PERMISSION rescue nil

            upsert_mcp_tool!(mcp_server, action_name, description, input_schema, "account", [required_permission].compact)
            synced_names << action_name
          rescue NameError => e
            Rails.logger.warn "[McpPlatformToolRegistrar] Skipping #{action_name}: #{e.message}"
          end

          # Sync introspection tools
          if defined?(Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS)
            Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS.each do |tool_def|
              name = tool_def[:name]
              upsert_mcp_tool!(
                mcp_server, name, tool_def[:description],
                tool_def[:input_schema]&.deep_stringify_keys || {},
                "account", tool_def[:required_permissions] || []
              )
              synced_names << name
            end
          end

          # Remove tools no longer in the registry
          stale_count = mcp_server.mcp_tools.where.not(name: synced_names.to_a).delete_all

          # Update server capabilities with tool count
          mcp_server.update_columns(
            capabilities: mcp_server.capabilities.merge("tool_count" => synced_names.size),
            last_health_check: Time.current
          )

          Rails.logger.info "[McpPlatformToolRegistrar] Synced #{synced_names.size} tools to database (removed #{stale_count} stale)"
          synced_names.size
        end

        def execute_tool(tool_id, params:, account:, user: nil, agent_id: nil, token: nil, mcp_agent: nil)
          tool_name = tool_id.delete_prefix("#{TOOL_ID_PREFIX}.")
          tool_class = find_tool_class(tool_name)
          raise ArgumentError, "Unknown platform tool: #{tool_name}" unless tool_class

          # SECURITY: Enforce permission at execution time (defense-in-depth)
          enforce_permission!(user: user, tool_class: tool_class, tool_id: tool_id, token: token)

          # Rate limiting per agent
          if agent_id
            Ai::Introspection::RateLimiter.check!(
              agent_id: agent_id,
              max_calls: Ai::Tools::BaseTool::MAX_CALLS_PER_EXECUTION,
              window: 60
            )
          end

          # Audit log
          Rails.logger.info(
            "[McpPlatformTool] Executing #{tool_id} " \
            "user=#{user&.id} account=#{account.id} agent=#{agent_id}"
          )

          execution_params = params.with_indifferent_access

          # Multi-action tools use an :action param to route internally.
          # Auto-inject the registry key as the action when the tool class
          # handles multiple registry entries (e.g. create_agent, list_agents
          # all map to AgentManagementTool).
          unless execution_params.key?(:action)
            needs_action = tool_class.definition[:parameters]&.key?(:action) ||
                           tool_class.action_definitions.size > 1
            execution_params[:action] = ACTION_ALIASES.fetch(tool_name, tool_name) if needs_action
          end

          tool_instance = tool_class.new(account: account, user: user, agent: mcp_agent)
          tool_instance.execute(params: execution_params)
        end

        private

        def enforce_permission!(user:, tool_class:, tool_id:, token: nil)
          required = tool_class::REQUIRED_PERMISSION
          return if required.nil?

          unless user
            raise ::Mcp::ProtocolService::PermissionDeniedError,
                  "Authentication required for #{tool_id}"
          end

          unless user.has_permission?(required)
            raise ::Mcp::ProtocolService::PermissionDeniedError,
                  "Permission denied for #{tool_id}: requires '#{required}'"
          end

          # Token permission intersection: if an MCP token is present with scoped
          # permissions, the token must also grant the required permission
          if token&.permissions.present? && !token.has_permission?(required)
            raise ::Mcp::ProtocolService::PermissionDeniedError,
                  "Token does not grant permission for #{tool_id}: requires '#{required}'"
          end
        end

        def upsert_mcp_tool!(mcp_server, name, description, input_schema, permission_level, required_permissions)
          tool = mcp_server.mcp_tools.find_or_initialize_by(name: name)
          tool.assign_attributes(
            description: description,
            input_schema: input_schema,
            enabled: true,
            permission_level: permission_level,
            required_permissions: required_permissions
          )
          tool.save!
        end

        def build_manifest(tool_class)
          definition = tool_class.definition
          {
            "name" => definition[:name],
            "description" => definition[:description],
            "type" => "platform_tool",
            "version" => "1.0.0",
            "category" => "platform",
            "permission_level" => "account",
            "required_permissions" => [tool_class::REQUIRED_PERMISSION].compact,
            "inputSchema" => convert_to_json_schema(definition[:parameters]),
            "outputSchema" => default_output_schema,
            "metadata" => { "tool_class" => tool_class.name },
            "rate_limited" => true,
            "rate_limit" => { "max_calls" => 20, "window_seconds" => 60 }
          }
        end

        def convert_to_json_schema(parameters)
          return { "type" => "object", "properties" => {}, "required" => [] } if parameters.blank?

          properties = {}
          required = []

          parameters.each do |param_name, param_def|
            properties[param_name.to_s] = {
              "type" => param_def[:type] || "string",
              "description" => param_def[:description]
            }.compact
            required << param_name.to_s if param_def[:required]
          end

          { "type" => "object", "properties" => properties, "required" => required }
        end

        def default_output_schema
          {
            "type" => "object",
            "properties" => {
              "success" => { "type" => "boolean" },
              "error" => { "type" => "string" }
            },
            "required" => ["success"]
          }
        end

        def tool_classes
          @tool_classes ||= PlatformApiToolRegistry::TOOLS.values.uniq.filter_map do |class_name|
            class_name.constantize
          rescue NameError => e
            Rails.logger.warn "[McpPlatformToolRegistrar] Tool class not found: #{class_name} - #{e.message}"
            nil
          end
        end

        def find_tool_class(tool_name)
          # Look up via the registry hash first (handles multi-action tools
          # where multiple registry keys map to one tool class)
          class_name = PlatformApiToolRegistry::TOOLS[tool_name]
          if class_name
            return class_name.constantize rescue nil
          end

          # Fall back to matching by definition name (single-action tools)
          tool_classes.find { |klass| klass.definition[:name] == tool_name }
        end
      end
    end
  end
end

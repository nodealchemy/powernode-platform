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
        "extract_to_knowledge_graph" => "extract",
        # Codebase Intelligence
        "code_context_tree" => "context_tree",
        "code_file_skeleton" => "file_skeleton",
        "code_semantic_search" => "semantic_search",
        "code_identifier_search" => "identifier_search",
        "code_semantic_navigate" => "semantic_navigate",
        "code_feature_hub" => "feature_hub",
        "code_blast_radius" => "blast_radius",
        "code_static_analysis" => "static_analysis",
        "code_index_status" => "index_status",
        "code_dead_code" => "dead_code",
        "code_find_duplicates" => "find_duplicates",
        "code_analyze_section" => "analyze_section",
        "code_upsert_node" => "upsert_node",
        "code_create_relation" => "create_relation",
        "code_search_graph" => "search_graph",
        "code_prune_stale" => "prune_stale",
        "code_bulk_index" => "bulk_index"
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

          # Sync platform tools from PlatformApiToolRegistry.all_tools
          PlatformApiToolRegistry.all_tools.each do |action_name, class_name|
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

        def execute_tool(tool_id, params:, account:, user: nil, agent_id: nil, token: nil, mcp_agent: nil, instance_authorized: false, node_instance: nil)
          tool_name = tool_id.delete_prefix("#{TOOL_ID_PREFIX}.")
          tool_class = find_tool_class(tool_name)
          raise ArgumentError, "Unknown platform tool: #{tool_name}" unless tool_class

          # SECURITY: Enforce permission at execution time (defense-in-depth)
          enforce_permission!(user: user, tool_class: tool_class, tool_id: tool_id, token: token, instance_authorized: instance_authorized)

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
          # all map to AgentManagementTool). A caller-supplied action wins, so
          # for an instance principal — authorized per tool NAME — it must first
          # be shown to agree with the name that authorization cleared.
          if execution_params.key?(:action)
            if instance_authorized
              enforce_action_scope!(tool_name: tool_name, tool_id: tool_id, tool_class: tool_class,
                                    supplied_action: execution_params[:action])
            end
          elsif action_dispatched?(tool_class)
            execution_params[:action] = ACTION_ALIASES.fetch(tool_name, tool_name)
          end

          tool_instance = tool_class.new(account: account, user: user, agent: mcp_agent)
          # Instance principals (mTLS node cert; user/agent both nil) need their
          # node_instance so DevLoopTool#claimant_ref can scope claims as
          # "instance:<id>" — otherwise claimant_ref is nil and every dev-loop
          # action hard-refuses. Guarded so the .new signature and the user/agent
          # paths (node_instance nil) stay byte-for-byte unchanged. (BUG-S)
          tool_instance.node_instance = node_instance if node_instance
          # ...and tell the tool this call already cleared the per-tool grant
          # gate (streamable_http_controller.rb may_invoke?), so a tool's own
          # per-action check can recognise a grant-gated instance principal
          # instead of inferring "internal caller" from the nil user — which
          # handed instances every per-action permission. Guarded so the
          # user/agent paths stay byte-for-byte unchanged. (IMP-9030413bc292)
          tool_instance.instance_authorized = true if instance_authorized
          tool_instance.execute(params: execution_params)
        end

        private

        # True when the tool routes on an :action param — one tool class serving
        # several registry keys, or declaring :action in its own schema. For
        # these the action, not the tool name, decides what actually runs.
        def action_dispatched?(tool_class)
          tool_class.definition[:parameters]&.key?(:action) ||
            tool_class.action_definitions.size > 1
        end

        # SECURITY (IMP-e8138c2714fb): make the action that RUNS agree with the
        # tool name the caller's grant was checked against.
        #
        # An instance principal is authorized by NAME: the streamable controller
        # runs Mcp::Principal#may_invoke?(tool_name) — grant globs plus the
        # destructive deny overlay — and everything downstream trusts that one
        # verdict (enforce_permission! returns early below, and a grant-gated
        # instance skips the tool's own per-action permission map). A
        # multi-action tool then ran whatever :action the caller supplied, so a
        # benign grant reached a destroy-shaped sibling on the same class:
        # platform.read_shared_memory carrying action "delete_shared_memory" is
        # a delete the overlay would never have granted by name.
        #
        # The flattened MCP surface advertises one tool name PER ACTION
        # (PlatformApiToolRegistry.tool_definitions), so a legitimate caller
        # never needs to disagree — it invokes the action's own name and the
        # branch above injects it. Requiring agreement is therefore the whole
        # fix: the executed action is, by construction, the name may_invoke?
        # already cleared.
        #
        # Scoped to instance principals deliberately. A user principal is bounded
        # by the per-action permission map inside the tool (has_permission? +
        # token intersection), which reads the SAME caller-supplied action, so
        # that path is left byte-for-byte unchanged.
        def enforce_action_scope!(tool_name:, tool_id:, tool_class:, supplied_action:)
          return unless action_dispatched?(tool_class)

          expected = ACTION_ALIASES.fetch(tool_name, tool_name)
          return if supplied_action.to_s == expected

          Rails.logger.warn(
            "[McpPlatformTool] Refused out-of-scope action for instance principal: " \
            "tool=#{tool_id} supplied_action=#{supplied_action} expected=#{expected}"
          )
          raise ::Mcp::ProtocolService::PermissionDeniedError,
                "Action '#{supplied_action}' is not permitted for #{tool_id}: an instance " \
                "principal is authorized per tool name, so #{tool_id} may only run '#{expected}'"
        end

        def enforce_permission!(user:, tool_class:, tool_id:, token: nil, instance_authorized: false)
          required = tool_class::REQUIRED_PERMISSION
          return if required.nil?

          # An instance principal (mTLS node cert, no User) that reached here was
          # ALREADY grant-gated by the streamable controller's may_invoke? check
          # (see streamable_http_controller.rb:563): that grant is what stands in
          # for its authorization. The grant is NAME-scoped, and enforce_action_scope!
          # above now holds the executed action to that same name, so what the
          # grant bounds is what runs. The intended downstream user:nil path is the
          # internal-caller bypass. Without this it was hard-denied -32001 for
          # every dev_next_task/dev_complete_task. (BUG-R — sibling of BUG-Q.)
          return if instance_authorized

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

          # If parameters already looks like a JSON Schema object (has "type" key), pass through
          if parameters.key?(:type) || parameters.key?("type")
            return parameters.deep_stringify_keys
          end

          properties = {}
          required = []

          parameters.each do |param_name, param_def|
            next unless param_def.is_a?(Hash)

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
          @tool_classes ||= PlatformApiToolRegistry.all_tools.values.uniq.filter_map do |class_name|
            class_name.constantize
          rescue NameError => e
            Rails.logger.warn "[McpPlatformToolRegistrar] Tool class not found: #{class_name} - #{e.message}"
            nil
          end
        end

        def find_tool_class(tool_name)
          # Look up via the registry hash first (handles multi-action tools
          # where multiple registry keys map to one tool class)
          class_name = PlatformApiToolRegistry.all_tools[tool_name]
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

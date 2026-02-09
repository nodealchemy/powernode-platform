# frozen_string_literal: true

module Ai
  module Tools
    class McpPlatformToolRegistrar
      TOOL_ID_PREFIX = "platform"

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

        def execute_tool(tool_id, params:, account:, user: nil, agent_id: nil)
          tool_name = tool_id.delete_prefix("#{TOOL_ID_PREFIX}.")
          tool_class = find_tool_class(tool_name)
          raise ArgumentError, "Unknown platform tool: #{tool_name}" unless tool_class

          # SECURITY: Enforce permission at execution time (defense-in-depth)
          enforce_permission!(user: user, tool_class: tool_class, tool_id: tool_id)

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

          tool_instance = tool_class.new(account: account)
          tool_instance.execute(params: params.symbolize_keys)
        end

        private

        def enforce_permission!(user:, tool_class:, tool_id:)
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
          tool_classes.find { |klass| klass.definition[:name] == tool_name }
        end
      end
    end
  end
end

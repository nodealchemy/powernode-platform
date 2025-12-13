# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # MCP Resource node executor - reads resources from MCP servers
    class McpResource < McpBase
      protected

      def perform_execution
        resource_uri = configuration["resource_uri"]
        log_info "Reading MCP Resource: #{resource_uri}"

        # Validate configuration
        unless resource_uri.present?
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "No resource_uri configured for MCP Resource node"
        end

        server = mcp_server

        # Render any template variables in the URI
        resolved_uri = render_template(resource_uri)
        log_debug "Resolved resource URI: #{resolved_uri}"

        # Read the resource
        service = McpResourceService.new(
          server: server,
          account: @orchestrator.account
        )

        result = service.read_resource(resolved_uri)

        if result[:success]
          # Store output in workflow variable if configured
          store_output_variable(result[:content])

          {
            output: result[:content],
            data: {
              mcp_server_id: server.id,
              mcp_server_name: server.name,
              resource_uri: resolved_uri,
              mime_type: result[:mime_type],
              content_length: result[:content]&.to_s&.length
            },
            result: result[:content],
            metadata: {
              node_id: @node.node_id,
              node_type: "mcp_resource",
              executed_at: Time.current.iso8601,
              resource_uri: resolved_uri
            }
          }
        else
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "MCP resource read failed: #{result[:error]}"
        end
      end
    end
  end
end

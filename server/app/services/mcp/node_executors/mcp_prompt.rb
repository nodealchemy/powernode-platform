# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # MCP Prompt node executor - invokes prompts from MCP servers
    class McpPrompt < McpBase
      protected

      def perform_execution
        prompt_name = configuration["prompt_name"]
        log_info "Executing MCP Prompt: #{prompt_name}"

        # Validate configuration
        unless prompt_name.present?
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "No prompt_name configured for MCP Prompt node"
        end

        server = mcp_server

        # Build prompt arguments from configuration and workflow variables
        arguments = build_prompt_arguments

        log_debug "MCP Prompt arguments: #{arguments.inspect}"

        # Execute the prompt
        service = Mcp::PromptService.new(
          server: server,
          account: @orchestrator.account
        )

        result = service.execute_prompt(prompt_name, arguments)

        if result[:success]
          # Store output in workflow variable if configured
          store_output_variable(result[:messages])

          {
            output: result[:messages],
            data: {
              mcp_server_id: server.id,
              mcp_server_name: server.name,
              prompt_name: prompt_name,
              message_count: result[:messages]&.length,
              description: result[:description]
            },
            result: result[:messages],
            metadata: {
              node_id: @node.node_id,
              node_type: "mcp_prompt",
              executed_at: Time.current.iso8601,
              prompt_name: prompt_name
            }
          }
        else
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "MCP prompt execution failed: #{result[:error]}"
        end
      end

      private

      # Build prompt arguments from configuration and workflow variables
      def build_prompt_arguments
        # Start with static arguments
        arguments = (configuration["arguments"] || {}).deep_dup

        # Apply argument mappings from workflow variables
        argument_mappings = configuration["argument_mappings"] || []
        argument_mappings.each do |mapping|
          arg_name = mapping["argument_name"] || mapping["parameter_name"]
          mapping_type = mapping["mapping_type"]

          value = case mapping_type
          when "static"
                    mapping["static_value"]
          when "variable"
                    get_variable(mapping["variable_path"])
          when "expression"
                    evaluate_expression(mapping["expression"])
          else
                    nil
          end

          arguments[arg_name] = value if value.present?
        end

        # Render any template values in arguments
        render_parameters(arguments)
      end
    end
  end
end

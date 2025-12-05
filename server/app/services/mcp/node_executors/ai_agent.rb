# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # AI Agent node executor - executes AI agents
    class AiAgent < Base
      protected

      def perform_execution
        agent_id = configuration['agent_id'] || configuration['ai_agent_id']

        unless agent_id
          raise Mcp::WorkflowOrchestrator::NodeExecutionError, "No agent_id configured for AI Agent node"
        end

        # Find the AI agent
        agent = ::AiAgent.find_by(id: agent_id)
        unless agent
          raise Mcp::WorkflowOrchestrator::NodeExecutionError, "AI Agent not found: #{agent_id}"
        end

        log_info "Executing AI Agent: #{agent.name}"

        # Prepare agent input from node configuration and context
        agent_input = prepare_agent_input

        log_debug "Agent input: #{agent_input.inspect}"

        # Execute agent via MCP agent executor
        execution_result = execute_agent(agent, agent_input)

        # Extract output from MCP execution result
        # MCP returns: { 'result' => { 'output' => ..., 'metadata' => ... }, 'telemetry' => ... }
        result_data = execution_result['result'] || execution_result[:result] || {}
        output_data = result_data['output'] || result_data[:output]
        result_metadata = result_data['metadata'] || result_data[:metadata] || {}

        # Store output in variables if configured
        if configuration['output_variable']
          set_variable(configuration['output_variable'], output_data)
        end

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: output_data,               # Primary result (universal key)
          data: {                                # Additional data
            agent_id: agent.id,
            agent_name: agent.name,
            agent_type: agent.agent_type,
            model: result_metadata['model_used'] || result_metadata[:model_used] || agent.mcp_metadata&.dig('model_config', 'model')
          },
          metadata: {                            # Execution metadata (standardized)
            node_id: @node.node_id,
            node_type: 'ai_agent',
            executed_at: Time.current.iso8601,
            cost: execution_result.dig('telemetry', 'cost') || 0.0,
            tokens_used: result_metadata['tokens_used'] || result_metadata[:tokens_used],
            duration_ms: result_metadata['processing_time_ms'] || result_metadata[:processing_time_ms],
            model: result_metadata['model_used'] || result_metadata[:model_used],
            # Agent-specific metadata
            agent_execution_id: @node_execution.ai_agent_execution&.id
          }
        }
      end

      private

      def prepare_agent_input
        # Check if there's a prompt template or prompt field
        prompt_template = configuration['prompt_template'] || configuration['prompt']

        if prompt_template.present?
          # Render template with variables from execution context
          rendered_prompt = render_template(prompt_template)

          {
            'input' => rendered_prompt,
            'context' => configuration['context'] || {}
          }
        else
          # Get input from node configuration
          input = {}

          # Map variables from execution context
          if configuration['input_mapping'].present?
            configuration['input_mapping'].each do |agent_param, variable_name|
              value = get_variable(variable_name)
              input[agent_param] = value if value.present?
            end
          end

          # Include direct input from configuration
          if configuration['input'].present?
            input.merge!(configuration['input'])
          end

          # Include node input data
          if input_data.present?
            input.merge!(input_data)
          end

          # If the agent expects an 'input' property but we've collected raw variables,
          # wrap them in the 'input' property for MCP schema compliance
          if input.present? && !input.key?('input')
            {
              'input' => input.map { |k, v| "#{k}: #{v}" }.join("\n"),
              'context' => configuration['context'] || {}
            }
          else
            input
          end
        end
      end

      def render_template(template)
        result = template.dup

        # Find all {{variable}} patterns and replace with values from execution context
        result.gsub(/\{\{(\w+)\}\}/) do |match|
          variable_name = $1
          value = get_variable(variable_name)
          value.present? ? value.to_s : match
        end
      end

      def create_agent_execution(agent, input)
        # Create an AiAgentExecution record to track this workflow-triggered execution
        AiAgentExecution.create!(
          ai_agent: agent,
          account: @orchestrator.account,
          user: @orchestrator.user,
          ai_provider: agent.ai_provider,
          execution_id: SecureRandom.uuid,
          status: 'pending',
          input_parameters: input,
          tokens_used: 0,
          cost_usd: 0.0,
          webhook_attempts: 0
        )
      end

      def execute_agent(agent, input)
        # Create AiAgentExecution record to track this agent execution
        # This ensures workflow-triggered agent executions are counted in agent stats
        agent_execution = create_agent_execution(agent, input)
        log_debug "Created agent execution record: #{agent_execution.execution_id}"

        # Link the AiAgentExecution to the AiWorkflowNodeExecution
        # This connects the workflow context to the agent execution
        @node_execution.update_column(:ai_agent_execution_id, agent_execution.id)
        log_debug "Linked agent execution to workflow node execution"

        # Start the agent execution
        agent_execution.start_execution!
        log_debug "Started agent execution tracking"

        # Use AI MCP agent executor for actual execution
        mcp_executor = AiMcpAgentExecutor.new(
          agent: agent,
          execution: agent_execution,
          account: @orchestrator.account
        )

        # Execute agent with input parameters
        execution_result = mcp_executor.execute(input)

        # Update agent execution with completion status
        # Check if execution returned an error response
        if execution_result['error'] || execution_result[:error]
          error_info = execution_result['error'] || execution_result[:error]
          error_message = error_info['message'] || error_info[:message] || 'Unknown MCP error'

          # Mark agent execution as failed
          agent_execution.fail_execution!(error_message, { 'mcp_error' => error_info })
          log_error "Agent execution failed: #{error_message}"

          @logger.error "[AI_AGENT_EXECUTOR] MCP error response: #{error_message}"
        elsif execution_result['result']
          # Execution succeeded
          result_data = execution_result['result']
          agent_execution.complete_execution!(
            { 'output' => result_data['output'] || result_data[:output] },
            {
              'tokens_used' => result_data.dig('metadata', 'tokens_used'),
              'processing_time_ms' => result_data.dig('metadata', 'processing_time_ms'),
              'model_used' => result_data.dig('metadata', 'model_used'),
              'provider' => result_data.dig('metadata', 'provider')
            }
          )

          # Record token usage and cost
          tokens = result_data.dig('metadata', 'tokens_used') || 0
          cost = execution_result.dig('telemetry', 'cost') || 0
          agent_execution.record_token_usage!(tokens, cost) if tokens > 0

          log_info "Agent execution completed successfully (tokens: #{tokens}, cost: $#{cost})"
        else
          # Unexpected response format
          agent_execution.fail_execution!(
            'Unexpected MCP response format',
            { 'response_keys' => execution_result.keys }
          )
          log_error "Unexpected MCP response format: #{execution_result.keys.inspect}"
          @logger.error "[AI_AGENT_EXECUTOR] Unexpected response format: #{execution_result.keys.inspect}"
        end

        execution_result
      rescue StandardError => e
        # Mark agent execution as failed if an error occurs
        agent_execution&.fail_execution!(e.message, { 'exception_class' => e.class.name })

        @logger.error "[AI_AGENT_EXECUTOR] Agent execution failed: #{e.message}"
        raise Mcp::WorkflowOrchestrator::NodeExecutionError,
              "AI Agent execution failed: #{e.message}"
      end
    end
  end
end

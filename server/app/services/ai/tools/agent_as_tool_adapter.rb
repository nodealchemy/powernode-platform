# frozen_string_literal: true

module Ai
  module Tools
    class AgentAsToolAdapter < BaseTool
      REQUIRED_PERMISSION = "ai.agents.execute"

      def initialize(account:, agent: nil, target_agent:)
        super(account: account, agent: agent)
        @target_agent = target_agent
      end

      class << self
        def definition_for(target_agent)
          {
            name: "invoke_agent_#{target_agent.name.parameterize(separator: '_')}",
            description: "Invoke the '#{target_agent.name}' AI agent. #{target_agent.description}",
            parameters: {
              prompt: {
                type: "string",
                description: "The input prompt or task to send to the agent",
                required: true
              },
              context: {
                type: "object",
                description: "Optional context data to pass to the agent",
                required: false
              }
            }
          }
        end

        def definition
          {
            name: "invoke_agent",
            description: "Invoke another AI agent as a tool",
            parameters: {
              agent_id: { type: "string", description: "Target agent ID", required: true },
              prompt: { type: "string", description: "Input prompt", required: true },
              context: { type: "object", description: "Optional context", required: false }
            }
          }
        end
      end

      protected

      def call(params)
        prompt = params[:prompt] || params["prompt"]
        context = params[:context] || params["context"] || {}

        validate_target_agent!

        execution = create_execution(prompt, context)

        {
          success: true,
          execution_id: execution.execution_id,
          agent_name: @target_agent.name,
          status: execution.status,
          message: "Agent '#{@target_agent.name}' execution started"
        }
      rescue StandardError => e
        Rails.logger.error "[AgentAsToolAdapter] Execution failed: #{e.message}"
        { success: false, error: e.message }
      end

      private

      def validate_target_agent!
        unless @target_agent.is_a?(Ai::Agent) && @target_agent.persisted?
          raise ArgumentError, "Invalid target agent"
        end

        unless @target_agent.is_active?
          raise ArgumentError, "Target agent '#{@target_agent.name}' is not active"
        end

        if @target_agent.account_id != @account.id
          raise ArgumentError, "Target agent does not belong to this account"
        end
      end

      def create_execution(prompt, context)
        Ai::AgentExecution.create!(
          ai_agent: @target_agent,
          account: @account,
          user_id: @agent&.respond_to?(:user_id) ? @agent.user_id : nil,
          execution_id: UUID7.generate,
          status: "queued",
          input_data: {
            prompt: prompt,
            context: context,
            invoked_by: @agent&.name || "tool_adapter",
            invocation_type: "agent_as_tool"
          },
          metadata: {
            source: "agent_as_tool",
            calling_agent_id: @agent&.id,
            priority: "normal"
          }
        )
      end
    end
  end
end

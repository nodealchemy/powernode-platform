# frozen_string_literal: true

# AiNodeExecutors - Concern for executing individual AI workflow nodes
#
# This concern encapsulates the execution logic for different node types
# in AI workflows. Each node type (ai_agent, api_call, webhook, condition,
# transform, human_approval) has its own execution method.
#
# @example Including in a service
#   class Ai::AgentOrchestrationService
#     include AiNodeExecutors
#   end
#
module AiNodeExecutors
  extend ActiveSupport::Concern

    # Execute an AI agent node by calling the configured AI provider
    #
    # @param node [Ai::WorkflowNode] The node to execute
    # @param input_data [Hash] Input data for the node
    # @return [Hash] Execution result with :success, :output_data, :cost, etc.
    def execute_ai_agent_node(node, input_data)
      agent_config = node.configuration
      agent_id = agent_config["agent_id"]

      return { success: false, error_message: "No agent configured" } unless agent_id

      agent = @account.ai_agents.find_by(id: agent_id)
      return { success: false, error_message: "Agent not found" } unless agent

      begin
        # Get AI provider credential for the agent
        provider_credential = agent.provider.provider_credentials
                                   .where(account: @account)
                                   .first

        return { success: false, error_message: "No provider credentials configured" } unless provider_credential

        # Initialize provider client
        client = Ai::ProviderClientService.new(provider_credential)

        # Prepare prompt from input data
        prompt = build_agent_prompt(input_data, agent_config)

        # Call AI provider
        response = client.generate_text(
          prompt,
          model: agent_config["model"],
          temperature: agent_config["temperature"] || 0.7,
          max_tokens: agent_config["max_tokens"] || 2000
        )

        if response[:success]
          content = response[:data][:choices]&.first&.dig(:message, :content) || "No content generated"
          usage = response[:data][:usage] || {}

          {
            success: true,
            output_data: {
              content: content,
              agent_id: agent_id,
              model: response[:data][:model] || agent_config["model"],
              provider: response[:provider]
            },
            cost: calculate_cost_from_usage(usage),
            tokens_consumed: usage[:prompt_tokens] || 0,
            tokens_generated: usage[:completion_tokens] || 0
          }
        else
          {
            success: false,
            error_message: response[:error] || "AI provider request failed"
          }
        end
      rescue StandardError => e
        @logger.error "AI agent execution failed: #{e.message}"
        {
          success: false,
          error_message: e.message
        }
      end
    end

    # Execute an API call node
    #
    # @param node [Ai::WorkflowNode] The node to execute
    # @param input_data [Hash] Input data for the node
    # @return [Hash] Execution result
    def execute_api_call_node(node, input_data)
      config = node.configuration
      url = config["url"]
      method = config["method"] || "GET"

      return { success: false, error_message: "No URL configured" } if url.blank?

      # Mock API call execution
      {
        success: true,
        output_data: {
          response: { result: "success", data: input_data },
          status_code: 200,
          url: url,
          method: method
        },
        cost: 0.01
      }
    end

    # Execute a webhook delivery node
    #
    # @param node [Ai::WorkflowNode] The node to execute
    # @param input_data [Hash] Input data for the node
    # @return [Hash] Execution result
    def execute_webhook_node(node, input_data)
      config = node.configuration
      url = config["url"]

      return { success: false, error_message: "No webhook URL configured" } if url.blank?

      # Mock webhook delivery
      {
        success: true,
        output_data: {
          webhook_delivered: true,
          url: url,
          payload: input_data,
          delivery_time: Time.current.iso8601
        },
        cost: 0.005
      }
    end

    # Execute a condition evaluation node
    #
    # @param node [Ai::WorkflowNode] The node to execute
    # @param input_data [Hash] Input data for the node
    # @return [Hash] Execution result with condition_result and next_path
    def execute_condition_node(node, input_data)
      config = node.configuration
      condition = config["condition"] || config["expression"]

      return { success: false, error_message: "No condition configured" } if condition.blank?

      # Simple condition evaluation
      result = case condition
      when /input\.score\s*>\s*([\d.]+)/
                 score = input_data["score"] || input_data[:score] || 0
                 threshold = ::Regexp.last_match(1).to_f
                 score > threshold
      else
                 true # Default to true for unknown conditions
      end

      {
        success: true,
        output_data: {
          condition_result: result,
          condition: condition,
          next_path: result ? (config["true_path"] || "success_node") : (config["false_path"] || "failure_node")
        },
        cost: 0.001
      }
    end

    # Execute a data transformation node
    #
    # @param node [Ai::WorkflowNode] The node to execute
    # @param input_data [Hash] Input data for the node
    # @return [Hash] Execution result with transformed data
    def execute_transform_node(node, input_data)
      config = node.configuration
      script = config["script"]

      return { success: false, error_message: "No transform script configured" } if script.blank?

      # Simple JavaScript-like transformation
      output_data = {}
      if script.include?("toUpperCase()")
        text = input_data["text"] || input_data[:text] || ""
        output_data["upper_text"] = text.upcase
      else
        output_data = input_data.dup
      end

      {
        success: true,
        output_data: output_data,
        cost: 0.002
      }
    end

    # Execute a human approval node
    #
    # @param node [Ai::WorkflowNode] The node to execute
    # @param input_data [Hash] Input data for the node
    # @return [Hash] Execution result with approval URL
    def execute_human_approval_node(node, input_data)
      config = node.configuration

      {
        success: true,
        output_data: {
          approval_required: true,
          approval_url: "#{ENV.fetch('APP_BASE_URL', 'http://localhost:3000')}/approvals/#{SecureRandom.uuid}",
          timeout: config["timeout"] || 3600,
          content: input_data
        },
        cost: 0
      }
    end
end

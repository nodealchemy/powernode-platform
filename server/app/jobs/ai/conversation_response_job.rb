# frozen_string_literal: true

module Ai
  # ConversationResponseJob - Generates AI responses for conversation messages
  #
  # Enqueued by AiConversationChannel#trigger_ai_response when a user sends
  # a message via WebSocket. Loads conversation history, calls the AI provider
  # via Ai::Llm::Client, and broadcasts the response back via the channel.
  #
  # When the agent has tools enabled (default), the LLM can call platform tools
  # (search_knowledge, query_learnings, etc.) via AgentToolBridgeService.
  #
  class ConversationResponseJob < ApplicationJob
    queue_as :ai_execution

    # Timeout for AI provider calls
    AI_RESPONSE_TIMEOUT = 120.seconds

    def perform(conversation_id, user_message_id, user_id)
      conversation = ::Ai::Conversation.find_by(id: conversation_id)
      return unless conversation

      agent = conversation.agent
      return unless agent

      provider = agent.provider
      return unless provider

      credential = provider.provider_credentials.where(is_active: true).first
      unless credential
        broadcast_error(conversation, "No active credentials configured for provider #{provider.name}")
        return
      end

      messages = build_messages_for_ai(conversation, agent)
      result = generate_response(credential, agent, messages)

      if result[:success]
        assistant_message = conversation.add_assistant_message(
          result[:content],
          broadcast: false,
          message_type: "text",
          token_count: result[:usage]&.dig(:total_tokens) || 0,
          cost_usd: calculate_cost(result[:usage], provider),
          processing_metadata: {
            model: result[:model],
            finish_reason: result[:finish_reason],
            usage: result[:usage],
            tool_calls: result[:tool_calls]
          }.compact
        )

        conversation.broadcast_ai_complete(assistant_message)
      else
        broadcast_error(conversation, result[:error] || "Failed to generate AI response")
      end
    rescue StandardError => e
      Rails.logger.error "[ConversationResponseJob] Error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
      broadcast_error(conversation, "AI response generation failed") if conversation
    end

    private

    def build_messages_for_ai(conversation, agent)
      messages = []

      if agent.system_prompt.present?
        messages << { role: "system", content: agent.system_prompt }
      end

      conversation.messages.order(sequence_number: :asc).last(20).each do |msg|
        messages << { role: msg.role, content: msg.content }
      end

      messages
    end

    def generate_response(credential, agent, messages)
      model = agent.model || credential.ai_provider.default_model
      llm_client = Ai::Llm::Client.new(provider: credential.provider, credential: credential)
      tool_bridge = Ai::AgentToolBridgeService.new(agent: agent)

      opts = {
        temperature: agent.temperature || 0.7,
        max_tokens: agent.max_tokens || 2048
      }

      # Extract system message as a separate parameter
      system_msg = messages.find { |m| m[:role] == "system" }
      if system_msg
        opts[:system_prompt] = system_msg[:content]
        messages = messages.reject { |m| m[:role] == "system" }
      end

      if tool_bridge.tools_enabled? && tool_bridge.tool_definitions_for_llm.any?
        result = tool_bridge.execute_tool_loop(
          llm_client: llm_client, messages: messages, model: model, **opts
        )
        {
          success: result[:content].present?,
          content: result[:content],
          model: model,
          usage: result[:usage],
          finish_reason: result[:finish_reason] || "stop",
          tool_calls: result[:tool_calls_log].presence
        }
      else
        response = llm_client.complete(messages: messages, model: model, **opts)
        if response.success?
          { success: true, content: response.content, model: model,
            usage: response.usage, finish_reason: response.finish_reason || "stop" }
        else
          { success: false, error: "Provider returned no content" }
        end
      end
    rescue StandardError => e
      Rails.logger.error "[ConversationResponseJob] Provider error: #{e.message}"
      { success: false, error: "AI service error: #{e.message}" }
    end

    def calculate_cost(usage, provider)
      return 0.0 unless usage

      input_tokens = usage[:prompt_tokens] || usage["prompt_tokens"] || 0
      output_tokens = usage[:completion_tokens] || usage["completion_tokens"] || 0

      pricing = provider.pricing_info || {}
      input_cost = pricing["input_cost_per_1k_tokens"] || 0.0
      output_cost = pricing["output_cost_per_1k_tokens"] || 0.0

      ((input_tokens / 1000.0) * input_cost + (output_tokens / 1000.0) * output_cost).round(6)
    end

    def broadcast_error(conversation, error_message)
      AiConversationChannel.broadcast_error(conversation, error_message)
    end
  end
end

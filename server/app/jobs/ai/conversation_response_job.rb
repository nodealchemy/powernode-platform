# frozen_string_literal: true

module Ai
  # ConversationResponseJob - Generates AI responses for conversation messages
  #
  # Enqueued by AiConversationChannel#trigger_ai_response when a user sends
  # a message via WebSocket. Loads conversation history, calls the AI provider,
  # and broadcasts the response back via the conversation channel.
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

      # Build conversation history for AI
      messages_for_ai = build_messages_for_ai(conversation, agent)

      # Generate AI response
      result = generate_response(credential, agent, messages_for_ai)

      if result[:success]
        # Create assistant message
        assistant_message = conversation.add_assistant_message(
          result[:content],
          message_type: "text",
          token_count: result[:usage]&.dig(:total_tokens) || 0,
          cost_usd: calculate_cost(result[:usage], provider),
          processing_metadata: {
            model: result[:model],
            finish_reason: result[:finish_reason],
            usage: result[:usage]
          }
        )

        # Broadcast the completed AI response
        AiConversationChannel.broadcast_ai_complete(conversation, assistant_message)
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

      # Include last 20 messages for context window
      conversation.messages.order(sequence_number: :asc).last(20).each do |msg|
        messages << { role: msg.role, content: msg.content }
      end

      messages
    end

    def generate_response(credential, agent, messages)
      model = agent.model || credential.ai_provider.default_model

      client = ::Ai::ProviderClientService.new(credential)

      result = client.send_message(messages, {
        model: model,
        temperature: agent.temperature || 0.7,
        max_tokens: agent.max_tokens || 2048
      })

      if result[:success]
        response_data = result[:response]
        content = extract_content(response_data)

        {
          success: true,
          content: content,
          model: model,
          usage: response_data&.dig(:usage),
          finish_reason: response_data&.dig(:choices, 0, :finish_reason) || "stop"
        }
      else
        { success: false, error: result[:error] || "Provider returned an error" }
      end
    rescue StandardError => e
      Rails.logger.error "[ConversationResponseJob] Provider error: #{e.message}"
      { success: false, error: "AI service error: #{e.message}" }
    end

    def extract_content(data)
      return "" unless data

      if data.is_a?(String)
        data
      elsif data[:content].is_a?(Array)
        data[:content].map { |c| c[:text] || c["text"] }.compact.join("\n")
      elsif data[:content].is_a?(String)
        data[:content]
      elsif data[:choices].is_a?(Array)
        data[:choices].first&.dig(:message, :content) ||
          data[:choices].first&.dig("message", "content") || ""
      elsif data[:message].is_a?(Hash)
        data[:message][:content] || data[:message]["content"] || ""
      elsif data[:response]
        data[:response]
      else
        data.to_s
      end
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

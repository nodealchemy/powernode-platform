# frozen_string_literal: true

# Service for handling streaming AI operations with real-time token delivery
# Integrates with WorkerLlmClient for provider streaming via the worker
class Ai::StreamingService
  include ActiveModel::Model

  attr_accessor :execution, :channel, :account

  def initialize(execution:, channel: nil, account: nil)
    @execution = execution
    @channel = channel
    @account = account || execution.account
    @buffer = []
    @stream_id = SecureRandom.uuid
    @start_time = Time.current
    @token_count = { prompt: 0, completion: 0, total: 0 }
  end

  # Stream AI agent execution with real-time token delivery
  # @param agent [AiAgent] The agent to execute
  # @param input_parameters [Hash] Input parameters for the execution
  # @return [Hash] Final execution result
  def stream_execution(agent, input_parameters)
    Rails.logger.info "[STREAMING] Starting stream #{@stream_id} for agent #{agent.id}"

    # Broadcast stream start
    broadcast_stream_event("stream_started", {
      stream_id: @stream_id,
      agent_id: agent.id,
      agent_name: agent.name,
      started_at: Time.current.iso8601
    })

    begin
      # Get provider client for the agent
      provider_client = get_provider_client(agent)

      if provider_client.nil?
        raise StandardError, "No valid provider credentials found for agent"
      end

      # Build messages from input parameters
      messages = build_messages(agent, input_parameters)

      # Get model from agent configuration or use provider default
      model = agent.model_config&.dig("model_id") ||
              agent.configuration&.dig("model") ||
              agent.provider&.default_model

      # Stream with real provider
      result = stream_with_provider(provider_client, messages, model, agent)

      # Complete streaming
      complete_stream(result[:content], result[:usage])

    rescue StandardError => e
      handle_stream_error(e)
    end
  end

  # Stream a conversation message with real-time token delivery
  # @param conversation [AiConversation] The conversation
  # @param message_content [String] The user's message
  # @param agent [AiAgent] The agent handling the conversation
  # @return [Hash] Final execution result
  def stream_conversation_message(conversation, message_content, agent)
    Rails.logger.info "[STREAMING] Starting conversation stream #{@stream_id}"

    broadcast_stream_event("stream_started", {
      stream_id: @stream_id,
      conversation_id: conversation.id,
      agent_id: agent.id,
      started_at: Time.current.iso8601
    })

    begin
      provider_client = get_provider_client(agent)

      if provider_client.nil?
        raise StandardError, "No valid provider credentials found for agent"
      end

      # Build messages from conversation history
      messages = build_conversation_messages(conversation, message_content, agent)

      model = agent.model_config&.dig("model_id") ||
              agent.configuration&.dig("model") ||
              agent.provider&.default_model

      result = stream_with_provider(provider_client, messages, model, agent)
      complete_stream(result[:content], result[:usage])

    rescue StandardError => e
      handle_stream_error(e)
    end
  end

  # Process a stream chunk and broadcast update
  def process_stream_chunk(chunk_data)
    return unless chunk_data[:content]

    @buffer << chunk_data[:content]
    @token_count[:completion] += estimate_tokens(chunk_data[:content])

    # Broadcast chunk to connected clients
    broadcast_stream_event("stream_chunk", {
      stream_id: @stream_id,
      chunk_index: @buffer.size - 1,
      content: chunk_data[:content],
      accumulated_content: chunk_data[:accumulated_content],
      buffer_size: @buffer.size,
      elapsed_ms: ((Time.current - @start_time) * 1000).to_i
    })

    # Update execution with partial results periodically
    update_execution_progress if (@buffer.size % 10).zero?
  end

  # Complete the stream with final results
  def complete_stream(full_response, usage = nil)
    Rails.logger.info "[STREAMING] Completing stream #{@stream_id}"

    # Update token counts from actual usage data
    if usage
      @token_count = {
        prompt: usage[:prompt_tokens] || usage["prompt_tokens"] || 0,
        completion: usage[:completion_tokens] || usage["completion_tokens"] || 0,
        total: usage[:total_tokens] || usage["total_tokens"] || 0
      }
    end

    # Calculate cost
    cost = calculate_cost(@token_count, @execution.agent&.provider)

    final_data = {
      stream_id: @stream_id,
      full_response: full_response,
      total_chunks: @buffer.size,
      duration_ms: ((Time.current - @start_time) * 1000).to_i,
      completed_at: Time.current.iso8601,
      usage: @token_count,
      cost: cost
    }

    # Broadcast completion
    broadcast_stream_event("stream_completed", final_data)

    # Update execution with final results
    @execution.update!(
      output_data: {
        response: full_response,
        stream_metadata: final_data
      },
      status: "completed",
      completed_at: Time.current,
      tokens_used: @token_count[:total],
      cost_usd: cost
    )

    final_data
  end

  # Handle streaming errors
  def handle_stream_error(error)
    Rails.logger.error "[STREAMING] Stream error #{@stream_id}: #{error.message}"
    Rails.logger.error error.backtrace&.first(10)&.join("\n")

    error_data = {
      stream_id: @stream_id,
      error: error.message,
      error_class: error.class.name,
      partial_response: @buffer.join,
      failed_at: Time.current.iso8601
    }

    # Broadcast error
    broadcast_stream_event("stream_error", error_data)

    # Update execution with error
    @execution.update!(
      status: "failed",
      error_message: error.message,
      error_details: error_data,
      completed_at: Time.current
    )

    raise error
  end

  private

  def get_provider_client(agent)
    return nil unless agent.provider&.is_active?

    WorkerLlmClient.new(agent_id: agent.id)
  end

  def build_messages(agent, input_parameters)
    messages = []

    # Add system prompt from agent
    system_prompt = agent.metadata&.dig("system_prompt") || agent.mcp_metadata&.dig("system_prompt")
    if system_prompt.present?
      messages << { role: "system", content: system_prompt }
    end

    # Add user message from input
    user_content = input_parameters[:message] ||
                   input_parameters[:content] ||
                   input_parameters[:input] ||
                   input_parameters.to_s
    messages << { role: "user", content: user_content }

    messages
  end

  def build_conversation_messages(conversation, message_content, agent)
    messages = []

    # Add system prompt
    system_prompt = agent.metadata&.dig("system_prompt") || agent.mcp_metadata&.dig("system_prompt")
    if system_prompt.present?
      messages << { role: "system", content: system_prompt }
    end

    # Add conversation history (last N messages for context)
    history_limit = agent.configuration&.dig("context_window_messages") || 20
    recent_messages = conversation.ai_messages
                                 .where.not(sender_type: "system")
                                 .order(created_at: :desc)
                                 .limit(history_limit)
                                 .reverse

    recent_messages.each do |msg|
      role = msg.sender_type == "user" ? "user" : "assistant"
      messages << { role: role, content: msg.content }
    end

    # Add current user message
    messages << { role: "user", content: message_content }

    messages
  end

  def stream_with_provider(provider_client, messages, model, agent)
    accumulated_content = ""
    usage_data = nil

    # Use provider streaming via WorkerLlmClient#stream
    response = provider_client.stream(
      messages: messages,
      model: model,
      max_tokens: agent.configuration&.dig("max_tokens") || 2000,
      temperature: agent.configuration&.dig("temperature") || 0.7
    ) do |chunk|
      case chunk.type
      when :stream_start
        Rails.logger.debug "[STREAMING] Provider stream started: #{chunk.stream_id}"
      when :content_delta
        accumulated_content += chunk.content.to_s
        process_stream_chunk({
          content: chunk.content,
          accumulated_content: accumulated_content
        })
      when :stream_end
        usage_data = chunk.usage
        Rails.logger.debug "[STREAMING] Provider stream ended with #{usage_data} tokens"
      when :error
        raise StandardError, chunk.content
      end
    end

    # Use response usage if available from final response
    usage_data ||= response&.usage

    { content: accumulated_content, usage: usage_data }
  end

  def broadcast_stream_event(event_type, data)
    return unless @channel || @execution

    message = {
      type: event_type,
      data: data,
      timestamp: Time.current.iso8601
    }

    # Broadcast to execution-specific channel
    if @execution
      ActionCable.server.broadcast(
        "ai_execution_stream_#{@execution.id}",
        message
      )

      # Also broadcast to conversation channel if this is a conversation execution
      if @execution.respond_to?(:ai_conversation_id) && @execution.ai_conversation_id
        ActionCable.server.broadcast(
          "ai_conversation_#{@execution.ai_conversation_id}",
          message.merge(
            type: event_type == "stream_chunk" ? "ai_response_streaming" : event_type,
            execution_id: @execution.id
          )
        )
      end
    end

    # Also broadcast to account-level monitoring
    if @account
      ActionCable.server.broadcast(
        "ai_monitoring_#{@account.id}",
        message.merge(execution_id: @execution&.id)
      )
    end
  end

  def update_execution_progress
    return unless @execution

    progress_percentage = estimate_progress

    @execution.update!(
      performance_metrics: {
        progress_percentage: progress_percentage,
        chunks_processed: @buffer.size,
        elapsed_ms: ((Time.current - @start_time) * 1000).to_i,
        streaming: true,
        estimated_tokens: @token_count[:completion]
      }
    )
  end

  def estimate_progress
    # Estimate based on typical response sizes
    # Most responses are 100-500 tokens, so ~50-250 chunks
    estimated_total = 200
    [ (@buffer.size.to_f / estimated_total * 100).round(2), 99 ].min
  end

  def estimate_tokens(text)
    # Rough estimate: ~4 characters per token for English
    (text.length / 4.0).ceil
  end

  def calculate_cost(token_count, provider)
    return 0 unless provider

    # Get pricing from provider configuration or use defaults
    pricing = provider.configuration&.dig("pricing") || {}
    prompt_price = pricing["prompt_per_1k"] || 0.001
    completion_price = pricing["completion_per_1k"] || 0.002

    prompt_cost = (token_count[:prompt] / 1000.0) * prompt_price
    completion_cost = (token_count[:completion] / 1000.0) * completion_price

    (prompt_cost + completion_cost).round(6)
  end
end

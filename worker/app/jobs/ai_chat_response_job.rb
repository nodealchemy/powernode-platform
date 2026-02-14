# frozen_string_literal: true

# Async chat response generation with streaming broadcast
# Queue: ai_conversations (priority 2)
#
# Receives a conversation_id + message_id, fetches conversation history,
# calls the AI provider with streaming, and broadcasts each token chunk
# via the backend API -> ActionCable.
class AiChatResponseJob < BaseJob
  include AiJobsConcern
  include ChatStreamingConcern
  include ChatFallbackProvidersConcern

  sidekiq_options queue: 'ai_conversations', retry: 2

  # Minimum interval (seconds) between streaming chunk broadcasts
  STREAM_BROADCAST_INTERVAL = 0.15

  def execute(conversation_id, message_id, agent_id, account_id)
    validate_required_params(
      { 'conversation_id' => conversation_id, 'message_id' => message_id,
        'agent_id' => agent_id, 'account_id' => account_id },
      'conversation_id', 'message_id', 'agent_id', 'account_id'
    )

    # Idempotency check
    idempotency_key = "chat_response:#{message_id}"
    if already_processed?(idempotency_key)
      log_info("Chat response already processed", message_id: message_id)
      return
    end

    log_info("Starting chat response generation",
      conversation_id: conversation_id,
      message_id: message_id,
      agent_id: agent_id
    )

    @conversation_id = conversation_id
    @message_id = message_id
    start_time = Time.current

    begin
      # Fetch conversation + agent data from backend
      conv_response = backend_api_get("/api/v1/ai/conversations/#{conversation_id}")
      unless conv_response['success']
        broadcast_error(conversation_id, "Failed to fetch conversation")
        return
      end

      agent = fetch_agent(agent_id, account_id)
      return unless agent

      @agent_name = agent['name'] || 'AI Assistant'

      provider = agent['ai_provider'] || agent['provider']
      return broadcast_error(conversation_id, "Agent has no provider configured") unless provider

      # Fetch credentials
      credentials = fetch_credentials(provider['id'])
      return broadcast_error(conversation_id, "No active credentials for provider") unless credentials

      # Build message history
      messages = build_chat_messages(conversation_id, agent)

      # Call AI provider with streaming
      ai_result = call_provider_streaming(provider, credentials, agent, messages)

      duration_ms = ((Time.current - start_time) * 1000).to_i

      if ai_result[:success]
        # Broadcast completion with full message
        broadcast_complete(
          conversation_id,
          message_id,
          ai_result[:content],
          token_count: ai_result[:tokens_used] || 0,
          cost_usd: ai_result[:cost] || 0.0,
          model: ai_result[:model],
          duration_ms: duration_ms
        )

        mark_processed(idempotency_key, ttl: 3600)

        log_info("Chat response completed",
          conversation_id: conversation_id,
          duration_ms: duration_ms,
          tokens: ai_result[:tokens_used],
          cost: ai_result[:cost]
        )
      else
        broadcast_error(conversation_id, ai_result[:error] || "AI provider error")

        log_error("Chat response failed",
          conversation_id: conversation_id,
          error: ai_result[:error]
        )
      end
    rescue StandardError => e
      broadcast_error(conversation_id, "Internal error generating response")
      handle_ai_processing_error(e, {
        conversation_id: conversation_id,
        message_id: message_id,
        agent_id: agent_id
      })
    end
  end

  private

  def fetch_agent(agent_id, _account_id)
    response = backend_api_get("/api/v1/ai/agents/#{agent_id}")

    if response['success']
      response['data']['agent'] || response['data']
    else
      log_error("Failed to fetch agent", agent_id: agent_id)
      broadcast_error(nil, "Agent not found")
      nil
    end
  end

  def fetch_credentials(provider_id)
    response = backend_api_get("/api/v1/ai/credentials", {
      provider_id: provider_id,
      default_only: true,
      active: true
    })

    return nil unless response['success']

    creds = response['data']['credentials']
    creds.is_a?(Array) ? creds.first : creds
  end

  def build_chat_messages(conversation_id, agent)
    # Fetch recent message history
    response = backend_api_get("/api/v1/ai/conversations/#{conversation_id}", {})

    messages = []
    conversation = response['data']['conversation'] if response['success']

    # System prompt from agent
    system_prompt = agent['system_prompt']
    messages << { role: 'system', content: system_prompt } if system_prompt.present?

    # Add recent messages from conversation
    if conversation && conversation['recent_messages'].is_a?(Array)
      conversation['recent_messages'].each do |msg|
        next if msg['role'] == 'system'

        messages << { role: msg['role'], content: msg['content'] }
      end
    end

    messages
  end

  def call_provider_streaming(provider, credentials, agent, messages)
    provider_type = provider['provider_type']&.downcase || 'openai'
    model = agent['model'] || provider['default_model'] || 'gpt-4'
    temperature = agent['temperature'] || 0.7
    max_tokens = agent['max_tokens'] || 2048

    # Decrypt credentials
    decrypt_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    unless decrypt_response['success']
      return { success: false, error: 'Failed to decrypt credentials' }
    end

    api_key = decrypt_response['data']['api_key'] || decrypt_response['data']['decrypted_key']
    base_url = credentials['base_url'] || provider['base_url']

    case provider_type
    when 'openai', 'openai_compatible'
      call_openai_streaming(api_key, base_url, model, messages, temperature, max_tokens)
    when 'anthropic'
      call_anthropic_streaming(api_key, base_url, model, messages, temperature, max_tokens)
    when 'ollama'
      call_ollama_streaming(base_url, model, messages, temperature, max_tokens)
    else
      call_generic(api_key, base_url, model, messages, temperature, max_tokens)
    end
  end
end

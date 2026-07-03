# frozen_string_literal: true

# Shared plumbing for AI response jobs (AiChatResponseJob, AiWorkspaceResponseJob):
# the execute() template — validate/kill-switch/idempotency/fetch/dispatch/broadcast/
# rescue skeleton — plus the identical fetch_agent and call_provider_streaming
# implementations. Includers customize behavior via the hook methods below;
# everything else (messages building, credential fetching/decryption, broadcast
# target) stays job-specific because it differs meaningfully between chat and
# workspace responses.
module AiResponseJobConcern
  extend ActiveSupport::Concern

  def execute(conversation_id, message_id, agent_id, account_id)
    validate_required_params(
      { 'conversation_id' => conversation_id, 'message_id' => message_id,
        'agent_id' => agent_id, 'account_id' => account_id },
      'conversation_id', 'message_id', 'agent_id', 'account_id'
    )

    # Kill switch check — bail if AI activity is suspended for the account
    return if bail_if_ai_suspended!(account_id)

    idempotency_key = response_idempotency_key(message_id, agent_id)
    if already_processed?(idempotency_key)
      log_info("#{response_log_label} already processed", **already_processed_log_fields(message_id, agent_id))
      return
    end

    log_info("Starting #{response_log_label.downcase} generation",
      conversation_id: conversation_id, message_id: message_id, agent_id: agent_id)

    @conversation_id = conversation_id
    @message_id = message_id
    @agent_id = agent_id
    start_time = Time.current

    begin
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

      credentials = fetch_credentials(provider['id'])
      return broadcast_error(conversation_id, "No active credentials for provider") unless credentials

      messages = build_response_messages(conv_response, conversation_id, agent)

      ai_result = call_provider_streaming(provider, credentials, agent, messages)

      duration_ms = ((Time.current - start_time) * 1000).to_i

      if ai_result[:success]
        broadcast_response_complete(conversation_id, message_id, ai_result, duration_ms)
        mark_processed(idempotency_key, ttl: 3600)
        log_info("#{response_log_label} completed", **completion_log_fields(conversation_id, duration_ms, ai_result))
      else
        broadcast_error(conversation_id, ai_result[:error] || "AI provider error")
        log_error("#{response_log_label} failed", **failure_log_fields(conversation_id, ai_result))
      end
    rescue StandardError => e
      broadcast_error(conversation_id, rescue_broadcast_message)
      handle_ai_processing_error(e, rescue_context(conversation_id, message_id, agent_id))
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

  def call_provider_streaming(provider, credentials, agent, messages)
    provider_type = provider['provider_type']&.downcase || 'openai'
    model = agent['model'] || provider['default_model'] || 'gpt-4'
    temperature = agent['temperature'] || 0.7
    max_tokens = agent['max_tokens'] || 2048

    api_key, base_url = resolve_provider_credentials(credentials, provider)
    return { success: false, error: 'Failed to decrypt credentials' } if api_key == :decrypt_failed

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

  # --- Hook points implemented per-job ---
  #
  # response_idempotency_key(message_id, agent_id)
  # response_log_label
  # already_processed_log_fields(message_id, agent_id)
  # build_response_messages(conv_response, conversation_id, agent)
  # resolve_provider_credentials(credentials, provider) -> [api_key_or_:decrypt_failed, base_url]
  # broadcast_response_complete(conversation_id, message_id, ai_result, duration_ms)
  # completion_log_fields(conversation_id, duration_ms, ai_result)
  # failure_log_fields(conversation_id, ai_result)
  # rescue_broadcast_message
  # rescue_context(conversation_id, message_id, agent_id)
end

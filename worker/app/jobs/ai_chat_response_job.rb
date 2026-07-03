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
  include AiSuspensionCheckConcern
  include AiResponseJobConcern

  sidekiq_options queue: 'ai_conversations', retry: 2

  private

  def response_idempotency_key(message_id, _agent_id)
    "chat_response:#{message_id}"
  end

  def response_log_label
    "Chat response"
  end

  def already_processed_log_fields(message_id, _agent_id)
    { message_id: message_id }
  end

  def fetch_credentials(_provider_id)
    # Use the internal provider_config endpoint with agent_id (worker JWT authorized).
    # The endpoint resolves provider + credential from the agent record.
    response = api_client.post("/api/v1/internal/ai/provider_config", {
      agent_id: @agent_id || @agent_data&.dig("id")
    })

    return nil unless response && response["success"]

    config = response["data"] || response
    {
      "provider_type" => config["provider_type"],
      "provider_credential_id" => config["provider_credential_id"],
      "base_url" => config["provider_base_url"],
      "model" => config["model"],
      "provider_name" => config["provider_name"]
    }.compact.presence
  end

  def build_response_messages(_conv_response, conversation_id, agent)
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

  def resolve_provider_credentials(credentials, provider)
    decrypt_response = backend_api_post("/api/v1/internal/ai/credentials/#{credentials['id']}/decrypt")
    return [:decrypt_failed, nil] unless decrypt_response['success']

    api_key = decrypt_response['data']['api_key'] || decrypt_response['data']['decrypted_key']
    base_url = credentials['base_url'] || provider['base_url']
    [api_key, base_url]
  end

  def broadcast_response_complete(conversation_id, message_id, ai_result, duration_ms)
    broadcast_complete(
      conversation_id,
      message_id,
      ai_result[:content],
      token_count: ai_result[:tokens_used] || 0,
      cost_usd: ai_result[:cost] || 0.0,
      model: ai_result[:model],
      duration_ms: duration_ms
    )
  end

  def completion_log_fields(conversation_id, duration_ms, ai_result)
    {
      conversation_id: conversation_id,
      duration_ms: duration_ms,
      tokens: ai_result[:tokens_used],
      cost: ai_result[:cost]
    }
  end

  def failure_log_fields(conversation_id, ai_result)
    { conversation_id: conversation_id, error: ai_result[:error] }
  end

  def rescue_broadcast_message
    "Internal error generating response"
  end

  def rescue_context(conversation_id, message_id, agent_id)
    { conversation_id: conversation_id, message_id: message_id, agent_id: agent_id }
  end
end
